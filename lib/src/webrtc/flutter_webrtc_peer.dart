// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/stream_config.dart';
import 'stream_stats_parser.dart';
import 'webrtc_initializer.dart';
import '../core/stream_transports.dart';
import '../core/video_codecs.dart';
import '../protocol/stream_spec.dart';

/// Creates `flutter_webrtc` peer connections.
final class FlutterWebRtcPeerFactory implements PeerTransportFactory {
  /// Creates the factory.
  FlutterWebRtcPeerFactory();

  @override
  Future<PeerTransport> create(
    Map<String, Object?> rtcConfiguration, {
    required StreamConfig config,
    required bool muted,
  }) async {
    await webRtcInitializer.ensureInitialized();
    final pc = await createPeerConnection({
      ...rtcConfiguration,
      'sdpSemantics': 'unified-plan',
    });
    try {
      return await _FlutterWebRtcPeer.setUp(pc, muted, config.videoCodec);
    } on Object {
      await pc.close();
      await pc.dispose();
      rethrow;
    }
  }
}

/// `RTCDataChannelInit` that keeps `maxRetransmits: 0`, which the stock
/// `toMap` drops (it only sends values above 0), turning the hover channel
/// into a reliable one.
final class _ChannelInit extends RTCDataChannelInit {
  _ChannelInit(DataChannelSpec spec) {
    ordered = spec.ordered;
    negotiated = spec.negotiated;
    id = spec.id;
    _maxRetransmits = spec.maxRetransmits;
  }

  int? _maxRetransmits;

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'maxRetransmits': ?_maxRetransmits,
  };
}

ChannelState _channelState(RTCDataChannelState state) => switch (state) {
  RTCDataChannelState.RTCDataChannelConnecting => ChannelState.connecting,
  RTCDataChannelState.RTCDataChannelOpen => ChannelState.open,
  RTCDataChannelState.RTCDataChannelClosing => ChannelState.closing,
  RTCDataChannelState.RTCDataChannelClosed => ChannelState.closed,
};

PeerState _peerState(RTCPeerConnectionState state) => switch (state) {
  RTCPeerConnectionState.RTCPeerConnectionStateNew => PeerState.initial,
  RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
    PeerState.connecting,
  RTCPeerConnectionState.RTCPeerConnectionStateConnected => PeerState.connected,
  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
    PeerState.disconnected,
  RTCPeerConnectionState.RTCPeerConnectionStateFailed => PeerState.failed,
  RTCPeerConnectionState.RTCPeerConnectionStateClosed => PeerState.closed,
};

final class _Channel implements DataChannelTransport {
  _Channel(this._channel) {
    _channel.onDataChannelState = (state) => _states.add(_channelState(state));
  }

  final RTCDataChannel _channel;
  final StreamController<ChannelState> _states =
      StreamController<ChannelState>.broadcast(sync: true);

  @override
  ChannelState get state => _channelState(
    _channel.state ?? RTCDataChannelState.RTCDataChannelConnecting,
  );

  @override
  Stream<ChannelState> get states => _states.stream;

  @override
  void send(Uint8List data) {
    // The returned future only reports a failed send; nothing to wait for.
    unawaited(
      _channel.send(RTCDataChannelMessage.fromBinary(data)).catchError((
        Object _,
      ) {
        // A send racing a closing channel is dropped.
      }),
    );
  }

  Future<void> close() async {
    _channel.onDataChannelState = null;
    try {
      await _channel.close();
    } on Object {
      // Already closed.
    }
    await _states.close();
  }
}

final class _FlutterWebRtcPeer implements PeerTransport {
  _FlutterWebRtcPeer._(this._pc, this._muted, this._control, this._hover) {
    _pc.onConnectionState = (state) => _connectionStates.add(_peerState(state));
    _pc.onIceCandidate = (candidate) {
      final line = candidate.candidate;
      // The end-of-candidates event is not sent.
      if (line == null || line.isEmpty) return;
      _localCandidates.add(
        IceCandidateData(
          candidate: line,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ),
      );
    };
    _pc.onTrack = _onTrack;
  }

  static Future<_FlutterWebRtcPeer> setUp(
    RTCPeerConnection pc,
    bool muted,
    VideoCodec videoCodec,
  ) async {
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    final video = await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    try {
      final capabilities = await getRtpReceiverCapabilities('video');
      final codecs = capabilities.codecs ?? const <RTCRtpCodecCapability>[];
      final order = videoCodecOrder([
        for (final c in codecs) c.mimeType,
      ], preference: videoCodec);
      await video.setCodecPreferences([for (final i in order) codecs[i]]);
    } on Object {
      // Codec preferences are an optimisation: the platform default order is
      // negotiated without them.
    }
    final control = await pc.createDataChannel(
      StreamDataChannels.control.label,
      _ChannelInit(StreamDataChannels.control),
    );
    final hover = await pc.createDataChannel(
      StreamDataChannels.hover.label,
      _ChannelInit(StreamDataChannels.hover),
    );
    return _FlutterWebRtcPeer._(pc, muted, _Channel(control), _Channel(hover));
  }

  final RTCPeerConnection _pc;
  final _statsParser = StreamStatsParser();
  bool _muted;
  MediaStreamTrack? _audioTrack;
  MediaStream? _fallbackStream;
  bool _closed = false;
  final _Channel _control;
  final _Channel _hover;

  final StreamController<PeerState> _connectionStates =
      StreamController<PeerState>.broadcast(sync: true);
  final StreamController<IceCandidateData> _localCandidates =
      StreamController<IceCandidateData>.broadcast(sync: true);
  final StreamController<MediaStream> _remoteVideoStreams =
      StreamController<MediaStream>.broadcast(sync: true);

  Future<void> _onTrack(RTCTrackEvent event) async {
    final track = event.track;
    if (track.kind == 'audio') {
      // The audio track is negotiated either way; muting only disables it.
      _audioTrack = track;
      track.enabled = !_muted;
      return;
    }
    if (track.kind != 'video') return;
    // The backend sends audio and video under separate stream ids; the video
    // track's own stream is what a renderer needs.
    if (event.streams.isNotEmpty) {
      _emitVideo(event.streams.first);
      return;
    }
    // No stream ids: wrap the track in a stream this peer owns.
    final local = await createLocalMediaStream('mobilerun-remote');
    if (_closed) {
      await _disposeStream(local);
      return;
    }
    await local.addTrack(track);
    _fallbackStream = local;
    _emitVideo(local);
  }

  void _emitVideo(MediaStream stream) {
    if (!_remoteVideoStreams.isClosed) _remoteVideoStreams.add(stream);
  }

  static Future<void> _disposeStream(MediaStream? stream) async {
    try {
      await stream?.dispose();
    } on Object {
      // Already released.
    }
  }

  @override
  Stream<PeerState> get connectionStates => _connectionStates.stream;

  @override
  Stream<IceCandidateData> get localCandidates => _localCandidates.stream;

  @override
  Stream<MediaStream> get remoteVideoStreams => _remoteVideoStreams.stream;

  @override
  DataChannelTransport get control => _control;

  @override
  DataChannelTransport get hover => _hover;

  @override
  Future<String> createLocalOffer({bool iceRestart = false}) async {
    final offer = await _pc.createOffer(
      iceRestart
          ? {
              'mandatory': {
                'IceRestart': true,
                'OfferToReceiveAudio': true,
                'OfferToReceiveVideo': true,
              },
              'optional': <Object?>[],
            }
          : <String, dynamic>{},
    );
    await _pc.setLocalDescription(offer);
    return offer.sdp!;
  }

  @override
  Future<void> setRemoteAnswer(String sdp) =>
      _pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));

  @override
  Future<void> addRemoteCandidate(IceCandidateData candidate) =>
      _pc.addCandidate(
        RTCIceCandidate(
          candidate.candidate,
          candidate.sdpMid,
          candidate.sdpMLineIndex,
        ),
      );

  @override
  Future<void> setIceServers(Object? iceServers) =>
      _pc.setConfiguration({'iceServers': iceServers});

  @override
  void setAudioMuted(bool muted) {
    _muted = muted;
    _audioTrack?.enabled = !muted;
  }

  @override
  Future<VideoStats?> readVideoStats({
    Duration? sampleTime,
    bool publishStats = false,
    bool resetRates = false,
    double? timeToFirstFrameMs,
  }) async => _statsParser.read(
    (await _pc.getStats()).map(
      (report) => {
        ...report.values.cast<String, Object?>(),
        'id': report.id,
        'type': report.type,
      },
    ),
    sampleTime: sampleTime,
    publishStats: publishStats,
    resetRates: resetRates,
    timeToFirstFrameMs: timeToFirstFrameMs,
  );

  @override
  Future<void> close() async {
    _closed = true;
    _pc.onConnectionState = null;
    _pc.onIceCandidate = null;
    _pc.onTrack = null;
    await _control.close();
    await _hover.close();
    try {
      await _pc.close();
      await _pc.dispose();
    } on Object {
      // Already closed.
    }
    await _disposeStream(_fallbackStream);
    _fallbackStream = null;
    await _connectionStates.close();
    await _localCandidates.close();
    await _remoteVideoStreams.close();
  }
}
