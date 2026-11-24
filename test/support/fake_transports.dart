// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart'
    show MediaStream, MediaStreamTrack;
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/stream_transports.dart';

import 'fake_scheduler.dart';

import 'package:mobilerun_flutter/src/core/publish_transport.dart';

/// A frame the session sent, with the fake time it went out.
final class SentFrame {
  SentFrame(this.atMs, this.json);

  final int atMs;
  final Map<String, Object?> json;

  String get type => json['type']! as String;
}

final class FakeConnection implements SignallingConnection {
  FakeConnection(this._scheduler, this.uri);

  final FakeScheduler _scheduler;
  final Uri uri;
  final StreamController<String> _incoming = StreamController<String>();
  final List<SentFrame> sent = [];
  bool closedByClient = false;
  int? closeCode;
  Completer<void>? closeGate;
  bool closedByServer = false;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String frame) {
    if (closedByClient || closedByServer) {
      throw StateError('socket closed');
    }
    sent.add(
      SentFrame(
        _scheduler.nowMs,
        (jsonDecode(frame) as Map).cast<String, Object?>(),
      ),
    );
  }

  @override
  Future<void> close({int code = 1000}) async {
    closeCode = code;
    closedByClient = true;
    await closeGate?.future;
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  /// Server -> client text frame.
  void receive(Object message) =>
      _incoming.add(message is String ? message : jsonEncode(message));

  /// The server (or the network) closes the socket.
  void serverClose() {
    closedByServer = true;
    unawaited(_incoming.close());
  }

  List<SentFrame> ofType(String type) =>
      sent.where((f) => f.type == type).toList();
}

final class FakeConnector implements SignallingConnector {
  FakeConnector(this._scheduler);

  final FakeScheduler _scheduler;
  final List<FakeConnection> connections = [];
  final List<Uri> uris = [];

  /// Holds the next connect until it completes; otherwise connects at once.
  Completer<void>? gate;

  /// Throws on the next connects while set.
  Object? failWith;

  @override
  Future<SignallingConnection> connect(Uri uri) async {
    uris.add(uri);
    final error = failWith;
    if (error != null) throw error;
    final pending = gate;
    final connection = FakeConnection(_scheduler, uri);
    connections.add(connection);
    if (pending != null) {
      gate = null;
      await pending.future;
    }
    return connection;
  }

  FakeConnection get last => connections.last;
}

final class FakeChannel implements DataChannelTransport {
  final StreamController<ChannelState> _states =
      StreamController<ChannelState>.broadcast(sync: true);
  final List<Uint8List> sent = [];
  ChannelState _state = ChannelState.connecting;

  @override
  ChannelState get state => _state;

  @override
  Stream<ChannelState> get states => _states.stream;

  @override
  void send(Uint8List data) => sent.add(data);

  void setState(ChannelState state) {
    _state = state;
    _states.add(state);
  }
}

final class FakeMediaStream implements MediaStream {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class FakePeer implements PeerTransport, PublishPeerTransport {
  FakePeer(this.offerSdp, {required this.muted});

  final String offerSdp;
  @override
  Set<PublishKind> publishKinds = {PublishKind.audio, PublishKind.video};
  bool usablePublishSenders = true;
  Completer<void>? attachGate;
  PublishKind? failAttach;
  final attached = <PublishKind, MediaStreamTrack?>{};
  final publishCalls = <String>[];

  @override
  Future<bool> canAttachPublish(List<PublishKind> kinds) async =>
      usablePublishSenders;

  @override
  Future<void> replacePublishTrack(
    PublishKind kind,
    MediaStreamTrack? track,
  ) async {
    publishCalls.add('${kind.name}:${track == null ? "detach" : "attach"}');
    if (track != null) {
      await attachGate?.future;
      if (failAttach == kind) throw StateError('attach failed');
    }
    attached[kind] = track;
  }

  bool muted;

  final StreamController<PeerState> _states =
      StreamController<PeerState>.broadcast(sync: true);
  final StreamController<IceCandidateData> _candidates =
      StreamController<IceCandidateData>.broadcast(sync: true);
  final StreamController<MediaStream> _streams =
      StreamController<MediaStream>.broadcast(sync: true);
  final FakeChannel controlChannel = FakeChannel();
  final FakeChannel hoverChannel = FakeChannel();

  /// Everything the session asked of the peer, in order.
  final List<String> calls = [];
  bool closed = false;
  Object? setIceServersError;
  VideoStats? stats;
  Completer<VideoStats?>? statsGate;
  Completer<void>? closeGate;
  int reads = 0, activeReads = 0, maxActiveReads = 0;
  final sampleTimes = <Duration>[];
  double? lastTimeToFirstFrameMs;
  Object? statsError;

  @override
  Stream<PeerState> get connectionStates => _states.stream;

  @override
  Stream<IceCandidateData> get localCandidates => _candidates.stream;

  @override
  Stream<MediaStream> get remoteVideoStreams => _streams.stream;

  @override
  DataChannelTransport get control => controlChannel;

  @override
  DataChannelTransport get hover => hoverChannel;

  @override
  Future<String> createLocalOffer({bool iceRestart = false}) async {
    calls.add(iceRestart ? 'createOffer(iceRestart)' : 'createOffer');
    return iceRestart ? '$offerSdp#restart' : offerSdp;
  }

  @override
  Future<void> setRemoteAnswer(String sdp) async {
    calls.add('setRemoteAnswer');
  }

  @override
  Future<void> addRemoteCandidate(IceCandidateData candidate) async {
    calls.add('addCandidate ${candidate.candidate}');
  }

  @override
  Future<void> setIceServers(Object? servers) async {
    calls.add('setIceServers');
    final error = setIceServersError;
    if (error != null) throw error;
  }

  @override
  void setAudioMuted(bool muted) => this.muted = muted;

  @override
  Future<VideoStats?> readVideoStats({
    Duration? sampleTime,
    bool publishStats = false,
    bool resetRates = false,
    double? timeToFirstFrameMs,
  }) async {
    reads++;
    activeReads++;
    if (activeReads > maxActiveReads) maxActiveReads = activeReads;
    if (publishStats && sampleTime != null) sampleTimes.add(sampleTime);
    lastTimeToFirstFrameMs = timeToFirstFrameMs;
    try {
      if (statsError != null) throw statsError!;
      final value = statsGate == null ? stats : await statsGate!.future;
      return value == null
          ? null
          : VideoStats(
              width: value.width,
              height: value.height,
              framesDecoded: value.framesDecoded,
              sample: publishStats ? value.sample : null,
            );
    } finally {
      activeReads--;
    }
  }

  @override
  Future<void> close() async {
    await closeGate?.future;
    closed = true;
    calls.add('close');
  }

  // ---- test controls ------------------------------------------------------
  void emitState(PeerState state) => _states.add(state);

  void emitLocalCandidate(IceCandidateData candidate) =>
      _candidates.add(candidate);

  void emitVideo(MediaStream stream) => _streams.add(stream);
}

final class FakePeerFactory implements PeerTransportFactory {
  FakePeerFactory(this.offerSdp);

  final String offerSdp;
  final List<FakePeer> peers = [];
  Set<PublishKind> publishKinds = {PublishKind.audio, PublishKind.video};
  final List<Map<String, Object?>> configurations = [];

  @override
  Future<PeerTransport> create(
    Map<String, Object?> rtcConfiguration, {
    required StreamConfig config,
    required bool muted,
  }) async {
    configurations.add(rtcConfiguration);
    final peer = FakePeer(offerSdp, muted: muted)
      ..publishKinds = Set.of(publishKinds);
    peers.add(peer);
    return peer;
  }

  FakePeer get last => peers.last;
}

final class FakeCaptureTrack extends MediaStreamTrack {
  FakeCaptureTrack(this.kind);
  @override
  final String kind;
  bool stopped = false;
  @override
  bool enabled = true;
  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class FakePublishMedia implements PublishMedia {
  FakePublishMedia(bool video)
    : tracks = [
        FakeCaptureTrack('audio'),
        if (video) FakeCaptureTrack('video'),
      ];
  @override
  final List<FakeCaptureTrack> tracks;
  @override
  Future<void> stop() async {
    for (final track in tracks) {
      track.onEnded = null;
      await track.stop();
    }
  }
}

final class FakePublishCapture implements PublishCapture {
  int calls = 0;
  Object? error;
  Completer<void>? gate;
  final media = <FakePublishMedia>[];
  @override
  Future<PublishMedia> capture(
    PublishOptions options, {
    required bool Function() isCancelled,
    required void Function(PublishMedia media) onAcquired,
  }) async {
    calls++;
    await gate?.future;
    if (error != null) throw error!;
    final result = FakePublishMedia(options.video);
    media.add(result);
    onAcquired(result);
    return result;
  }
}
