// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'fake_scheduler.dart';

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
  Future<void> close() async {
    closedByClient = true;
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

  /// Completes the next connect when set; otherwise connects immediately.
  Completer<FakeConnection>? gate;

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
      pending.future.ignore();
      final value = await pending.future;
      return value;
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

final class FakePeer implements PeerTransport {
  FakePeer(this.scheduler, this.offerSdp, this.iceServers);

  final FakeScheduler scheduler;
  final String offerSdp;
  final Map<String, Object?> iceServers;

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
  VideoSize? size;

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
  Future<VideoSize?> readVideoSize() async => size;

  @override
  Future<void> close() async {
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
  FakePeerFactory(this.scheduler, this.offerSdp);

  final FakeScheduler scheduler;
  final String offerSdp;
  final List<FakePeer> peers = [];
  final List<Map<String, Object?>> configurations = [];

  @override
  Future<PeerTransport> create(
    Map<String, Object?> rtcConfiguration, {
    required StreamConfig config,
  }) async {
    configurations.add(rtcConfiguration);
    final peer = FakePeer(scheduler, offerSdp, rtcConfiguration);
    peers.add(peer);
    return peer;
  }

  FakePeer get last => peers.last;
}
