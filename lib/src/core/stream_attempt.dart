// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../protocol/signalling.dart';
import '../protocol/stream_timing.dart';
import 'scheduler.dart';
import 'stream_config.dart';
import 'stream_credentials.dart';
import 'stream_exception.dart';
import 'stream_status.dart';
import 'stream_stats.dart';
import 'stream_transports.dart';

/// What an attempt reports to its session. Callbacks fire only while the
/// attempt is live: a disposed attempt is silent.
final class StreamAttemptEvents {
  /// Creates the callback set.
  const StreamAttemptEvents({
    required this.connected,
    required this.disconnected,
    required this.failed,
    required this.videoStream,
    required this.videoSize,
    required this.credentialsRejected,
    required this.stats,
  });

  /// One-second sample, null on a disconnect.
  final void Function(StreamStats? stats) stats;

  /// The peer connection reached connected.
  final void Function() connected;

  /// The peer connection left connected outside an ICE restart.
  final void Function() disconnected;

  /// A terminal failure; the attempt has already released everything.
  final void Function() failed;

  /// The stream with the remote video track arrived.
  final void Function(MediaStream stream) videoStream;

  /// The decoded video size was read.
  final void Function(VideoSize size) videoSize;

  /// The server refused the token.
  final void Function() credentialsRejected;
}

/// One connect attempt of a stream: the counterpart of `start()` in
/// `use-webrtc-connection.ts` and everything it owns (socket, peer
/// connection, timers). Disposing it releases all of it.
final class StreamAttempt {
  /// Creates an attempt. Nothing happens before [start].
  StreamAttempt({
    required this.sessionId,
    required this.transports,
    required this.scheduler,
    required this.config,
    required this.muted,
    required this.credentials,
    required this.events,
    bool visible = true,
  }) : _visible = visible,
       _startedAt = scheduler.now;

  /// The streaming session id sent with every message.
  final String sessionId;

  /// The transports to build the connection on.
  final StreamTransports transports;

  /// The clock of all timers.
  final Scheduler scheduler;

  /// The session options.
  final StreamConfig config;

  /// The initial state of the audio track.
  final bool muted;

  /// Resolved target for this attempt. Discovery belongs to the session.
  final StreamCredentials credentials;

  /// The session callbacks.
  final StreamAttemptEvents events;

  static int _screenshotSequence = 0;

  /// Whether the attempt still runs. False after [dispose] or a failure.
  bool live = true;

  SignallingConnection? _connection;
  StreamSubscription<String>? _socketSubscription;
  PeerTransport? _peer;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<ScheduledTask> _timers = [];
  ScheduledTask? _keepAlive;
  ScheduledTask? _sizePoll;
  bool _polling = false;
  bool _statsEnabled = false;
  bool _resetRates = true;
  int _sampleEpoch = 0;
  Duration? _nextStatsAt;
  final Duration _startedAt;
  double? _firstFrameMs;
  ScheduledTask? _graceTimer;
  bool _requestedFrames = false;
  bool _visible = true;

  // The first rtcConfiguration reply ends the awaiting phase; later ones are
  // credential refreshes.
  final Completer<RtcConfigurationMessage> _rtcConfiguration = Completer();
  SignallingPhase get _phase => _rtcConfiguration.isCompleted
      ? SignallingPhase.active
      : SignallingPhase.awaitingRtcConfiguration;

  // ICE buffering of the current ICE generation.
  bool _remoteDescriptionSet = false;
  final List<IceCandidateData> _pendingCandidates = [];

  PeerState _peerState = PeerState.initial;
  bool _suppressedDip = false;
  final Map<String, _PendingScreenshot> _screenshots = {};

  /// Whether a non-terminal connection state dip is suppressed because a
  /// credential refresh restarts ICE.
  bool get _inGrace => _graceTimer != null;

  bool get _signallingOpen => live && _connection != null;

  /// Arms the keepAlive timer (at mount, like the web client) and connects.
  void start() {
    if (_visible) _scheduleKeepAlive();
    unawaited(_run());
  }

  /// Mirrors tab visibility: hidden apps stop sending keepAlive messages.
  void setVisible(bool visible) {
    if (_visible == visible || !live) return;
    _visible = visible;
    _keepAlive?.cancel();
    _keepAlive = null;
    if (visible) _scheduleKeepAlive();
  }

  // ---- requests -----------------------------------------------------------

  /// Sends [data] on the control channel; false while it is not open.
  bool sendControl(Uint8List data) => _sendOn(_peer?.control, data);

  /// Sends [data] on the hover channel; false while it is not open.
  bool sendHover(Uint8List data) => _sendOn(_peer?.hover, data);

  bool _sendOn(DataChannelTransport? channel, Uint8List data) {
    if (!live || channel == null || channel.state != ChannelState.open) {
      return false;
    }
    try {
      channel.send(data);
      return true;
    } on Object {
      return false;
    }
  }

  /// Asks the device to open [url]; false while the socket is not open.
  bool openUrl(String url) {
    if (!_signallingOpen) return false;
    return _send(OpenUrlMessage.fromInput(input: url, sessionId: sessionId));
  }

  /// Mutes or unmutes the audio track.
  void setMuted(bool muted) => _peer?.setAudioMuted(muted);

  /// Requests a screenshot, see `DeviceStreamSession.screenshot`.
  Future<Uint8List> screenshot(Duration timeout) {
    if (!_signallingOpen) {
      return Future.error(
        const StreamSessionException('stream is not connected'),
      );
    }
    final id =
        'ui-ss-${DateTime.now().millisecondsSinceEpoch}-'
        '${_screenshotSequence++}';
    final completer = Completer<Uint8List>();
    final pending = _PendingScreenshot(completer);
    _screenshots[id] = pending;
    pending.timer = scheduler.schedule(timeout, () {
      if (_screenshots.remove(id) == null) return;
      completer.completeError(
        TimeoutException('screenshot request timed out', timeout),
      );
    });
    if (!_send(ScreenshotRequestMessage(id: id))) {
      _screenshots.remove(id)?.timer?.cancel();
      return Future.error(
        const StreamSessionException('could not send screenshot request'),
      );
    }
    return completer.future;
  }

  // ---- negotiation --------------------------------------------------------

  bool _send(ClientMessage message) {
    final connection = _connection;
    if (!live || connection == null) return false;
    try {
      connection.send(message.encode());
      return true;
    } on Object {
      return false;
    }
  }

  void _scheduleKeepAlive() {
    _keepAlive = scheduler.schedule(SignallingTiming.keepAliveInterval, () {
      if (!live) return;
      _send(KeepAliveMessage(sessionId: sessionId));
      _scheduleKeepAlive();
    });
  }

  /// A terminal failure: release everything and tell the session.
  void _fail() {
    if (!live) return;
    unawaited(dispose());
    events.failed();
  }

  Future<T> _within<T>(Future<T> future, Duration timeout, String what) {
    final completer = Completer<T>();
    final timer = scheduler.schedule(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(what, timeout));
      }
    });
    _timers.add(timer);
    future.then(
      (value) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        timer.cancel();
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    return completer.future;
  }

  Future<void> _run() async {
    try {
      final connecting = transports.signalling.connect(
        credentials.toWebSocketUri(),
      );
      // A socket that opens after the attempt gave up is closed.
      unawaited(
        connecting.then<void>((connection) {
          if (!live) unawaited(connection.close());
        }, onError: (Object _) {}),
      );
      final connection = await _within(
        connecting,
        SignallingTiming.wsOpenTimeout,
        'WebSocket connection timeout',
      );
      if (!live) {
        unawaited(connection.close());
        return;
      }
      _connection = connection;

      // The socket closing is terminal for the session on the server, even
      // while the peer connection still reports connected.
      _socketSubscription = connection.messages.listen(
        _onMessage,
        onDone: _fail,
        onError: (Object _) {},
      );

      _send(RequestRtcConfigurationMessage(sessionId: sessionId));
      final configuration = await _within(
        _rtcConfiguration.future,
        SignallingTiming.rtcConfigTimeout,
        'RTCConfiguration timeout',
      );
      if (!live) return;

      final peer = await transports.peers.create(
        configuration.rtcConfiguration,
        config: config,
        muted: muted,
      );
      if (!live) {
        await peer.close();
        return;
      }
      _peer = peer;
      _wirePeer(peer);

      final sdp = await peer.createLocalOffer();
      if (!live) return;
      _send(OfferMessage(sdp: sdp, sessionId: sessionId));
    } on Object catch (error) {
      if (!live) return;
      if (error is SignallingRejectedException && error.isUnauthorized) {
        events.credentialsRejected();
      }
      _fail();
    }
  }

  void _wirePeer(PeerTransport peer) {
    _subscriptions
      ..add(peer.connectionStates.listen(_onPeerState))
      ..add(
        peer.localCandidates.listen(
          (candidate) => _send(
            ClientCandidateMessage(
              candidate: candidate.candidate,
              sdpMid: candidate.sdpMid,
              sdpMLineIndex: candidate.sdpMLineIndex,
              sessionId: sessionId,
            ),
          ),
        ),
      )
      ..add(
        peer.remoteVideoStreams.listen((stream) {
          if (!live) return;
          events.videoStream(stream);
          _pollVideoSize();
        }),
      )
      ..add(
        peer.control.states.listen((state) {
          if (state == ChannelState.open) _requestFrames();
        }),
      );
  }

  /// The control channel opened: request the first frames.
  void _requestFrames() {
    if (!live || _requestedFrames) return;
    _requestedFrames = true;
    for (var i = 0; i < SignallingTiming.requestFrameCount; i++) {
      _timers.add(
        scheduler.schedule(SignallingTiming.requestFrameInterval * i, () {
          if (live) _send(RequestFrameMessage(sessionId: sessionId));
        }),
      );
    }
  }

  void _pollVideoSize() {
    if (_polling) return;
    _polling = true;
    _readVideoSize();
  }

  /// The session owns eligibility, including suppressed ICE restart dips.
  void setStatsEnabled(bool enabled) {
    if (_statsEnabled == enabled) return;
    _statsEnabled = enabled;
    _resetRates = true;
    _sampleEpoch++;
    _nextStatsAt = enabled
        ? scheduler.now + SignallingTiming.statsInterval
        : null;
  }

  void _readVideoSize() {
    final peer = _peer;
    if (!live || peer == null) return;
    final now = scheduler.now;
    final epoch = _sampleEpoch;
    final resetRates = _resetRates;
    _resetRates = false;
    final publish = _statsEnabled && now >= _nextStatsAt!;
    if (publish) _nextStatsAt = now + SignallingTiming.statsInterval;
    unawaited(() async {
      try {
        final stats = await peer.readVideoStats(
          sampleTime: _statsEnabled ? now - _startedAt : null,
          publishStats: publish,
          resetRates: resetRates,
          timeToFirstFrameMs: _firstFrameMs,
        );
        if (live && stats != null) {
          events.videoSize(VideoSize(stats.width, stats.height));
          if (stats.framesDecoded > 0) {
            _firstFrameMs ??=
                (scheduler.now - _startedAt).inMicroseconds / 1000;
          }
          if (_statsEnabled && epoch == _sampleEpoch && publish) {
            events.stats(stats.sample);
          }
        }
      } on Object {
        // A malformed or failed read must never stop size/first-frame polling.
      }
      if (live) {
        var delay = _firstFrameMs == null
            ? SignallingTiming.firstFrameInterval
            : SignallingTiming.videoSizeInterval;
        if (_statsEnabled) {
          final untilSample = _nextStatsAt! - scheduler.now;
          if (untilSample < delay) delay = untilSample;
        }
        _sizePoll = scheduler.schedule(
          delay.isNegative ? Duration.zero : delay,
          _readVideoSize,
        );
      }
    }());
  }

  // ---- peer connection state ----------------------------------------------

  void _onPeerState(PeerState state) {
    if (!live) return;
    _peerState = state;
    if (state == PeerState.failed || state == PeerState.closed) {
      // Terminal: this peer connection will not come back on its own.
      _fail();
      return;
    }
    if (state == PeerState.connected) {
      _endGrace();
      events.connected();
      return;
    }
    if (_inGrace) {
      // Media keeps flowing on the old candidate pair while a credential
      // refresh restarts ICE: a transient dip is not a disconnect. The check
      // at the end of the grace window reports one that outlived it.
      _suppressedDip = true;
      return;
    }
    events.stats(null);
    events.disconnected();
  }

  void _startGrace() {
    _endGrace();
    _graceTimer = scheduler.schedule(SignallingTiming.iceRestartGrace, () {
      _graceTimer = null;
      if (!live) return;
      if (_suppressedDip && _peerState != PeerState.connected) {
        events.stats(null);
        events.disconnected();
      }
      _suppressedDip = false;
    });
  }

  void _endGrace() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _suppressedDip = false;
  }

  // ---- signalling messages ------------------------------------------------

  void _onMessage(String text) {
    if (!live) return;
    final ServerMessage? message;
    try {
      message = decodeServerMessage(text, phase: _phase);
    } on SignallingStartupException {
      _fail();
      return;
    }
    switch (message) {
      case null:
        return;
      case RtcConfigurationMessage():
        if (_phase == SignallingPhase.awaitingRtcConfiguration) {
          _rtcConfiguration.complete(message);
        } else {
          unawaited(_onRtcRefresh(message));
        }
      case AnswerMessage():
        unawaited(_onAnswer(message));
      case ServerCandidateMessage():
        unawaited(_onRemoteCandidate(message));
      case ScreenshotMessage():
        final pending = _screenshots.remove(message.id);
        if (pending == null) return;
        pending.timer?.cancel();
        try {
          pending.completer.complete(_decodeDataUri(message.dataUri));
        } on FormatException {
          pending.completer.completeError(
            const StreamSessionException('screenshot is not valid base64'),
          );
        }
      case ScreenshotErrorMessage():
        final pending = _screenshots.remove(message.id);
        if (pending == null) return;
        pending.timer?.cancel();
        pending.completer.completeError(
          StreamSessionException(message.message),
        );
    }
  }

  Future<void> _onAnswer(AnswerMessage message) async {
    final peer = _peer;
    if (peer == null) return;
    try {
      await peer.setRemoteAnswer(message.sdp);
    } on Object {
      // A stale answer (for a superseded ICE restart) is ignored: the newer
      // offer gets its own answer.
      return;
    }
    if (!live) return;
    _remoteDescriptionSet = true;
    final buffered = List.of(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in buffered) {
      if (!live) return;
      try {
        await peer.addRemoteCandidate(candidate);
      } on Object {
        // A candidate that does not apply is skipped.
      }
    }
  }

  Future<void> _onRemoteCandidate(ServerCandidateMessage message) async {
    final peer = _peer;
    if (peer == null) return;
    final candidate = IceCandidateData(
      candidate: message.candidate,
      sdpMid: message.sdpMid,
      sdpMLineIndex: message.sdpMLineIndex,
    );
    if (!_remoteDescriptionSet) {
      _pendingCandidates.add(candidate);
      return;
    }
    try {
      await peer.addRemoteCandidate(candidate);
    } on Object {
      // A candidate that does not apply is skipped.
    }
  }

  /// Mid-session credential refresh: apply the new ICE servers and restart ICE
  /// so both sides allocate with the fresh credentials before the old ones
  /// expire. Media continues on the old pair meanwhile.
  Future<void> _onRtcRefresh(RtcConfigurationMessage message) async {
    final peer = _peer;
    if (peer == null) return;
    final iceServers = message.rtcConfiguration['iceServers'];
    if (iceServers == null) return;
    try {
      await peer.setIceServers(iceServers);
    } on Object {
      return;
    }
    if (!live) return;
    _startGrace();
    try {
      final sdp = await peer.createLocalOffer(iceRestart: true);
      if (!live) return;
      // New ICE generation: buffer incoming candidates until the restart
      // answer arrives, applying them against the old remote description
      // would reject them on ufrag mismatch.
      _remoteDescriptionSet = false;
      _pendingCandidates.clear();
      _send(OfferMessage(sdp: sdp, sessionId: sessionId));
    } on Object {
      if (live) _endGrace();
    }
  }

  static Uint8List _decodeDataUri(String dataUri) {
    final comma = dataUri.indexOf(',');
    return base64Decode(comma < 0 ? dataUri : dataUri.substring(comma + 1));
  }

  // ---- teardown -----------------------------------------------------------

  Future<void>? _disposing;

  /// Releases the socket, peer connection, timers and subscriptions, and
  /// fails pending screenshots. Concurrent callers await the same teardown.
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    if (!live) return;
    live = false;
    _keepAlive?.cancel();
    _sizePoll?.cancel();
    _graceTimer?.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    for (final pending in _screenshots.values) {
      pending.timer?.cancel();
      pending.completer.completeError(
        const StreamSessionException('connection lost'),
      );
    }
    _screenshots.clear();
    // live is already false: close normally before cancellation so that the
    // channel can send its close frame without subscription teardown racing it.
    final connection = _connection, peer = _peer;
    if (connection != null) await connection.close(code: 1000);
    final socketSubscription = _socketSubscription;
    _socketSubscription = null;
    if (socketSubscription != null) await socketSubscription.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    if (peer != null) await peer.close();
  }
}

final class _PendingScreenshot {
  _PendingScreenshot(this.completer);

  final Completer<Uint8List> completer;
  ScheduledTask? timer;
}
