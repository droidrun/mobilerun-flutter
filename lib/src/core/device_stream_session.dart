// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../protocol/signalling.dart';
import '../protocol/stream_timing.dart';
import '../webrtc/default_transports.dart';
import 'reconnect_controller.dart';
import 'scheduler.dart';
import 'stream_config.dart';
import 'stream_credentials.dart';
import 'stream_status.dart';
import 'stream_transports.dart';

/// Thrown when a session request (a screenshot) cannot be served.
final class StreamSessionException implements Exception {
  /// Creates the exception with a human readable [message].
  const StreamSessionException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'StreamSessionException: $message';
}

/// A live stream session to one Mobilerun cloud device.
///
/// It speaks the same protocol as `@mobilerun/react`: WebSocket signalling,
/// a client-offered recvonly WebRTC connection and two negotiated data
/// channels. The signalling socket is the lifetime of the session on the
/// server, so a closed socket, like a failed or closed peer connection, makes
/// the session rebuild both through the reconnect controller (exponential
/// backoff, [StreamUnavailable] after the retry budget is spent).
///
/// The session reads no app lifecycle; the embedding app calls [start],
/// [retry] and [close].
final class DeviceStreamSession {
  /// Creates a session. Nothing connects before [start].
  ///
  /// [credentials] is asked for the stream URL and token, see
  /// [StreamCredentialsProvider].
  DeviceStreamSession({
    required StreamCredentialsProvider credentials,
    StreamConfig config = const StreamConfig(),
  }) : this.withTransports(
         credentials: credentials,
         config: config,
         transports: defaultStreamTransports(),
       );

  /// Creates a session on custom [transports] and clock, for tests and for
  /// embedders that bring their own WebRTC stack.
  @visibleForTesting
  DeviceStreamSession.withTransports({
    required StreamCredentialsProvider credentials,
    required StreamTransports transports,
    StreamConfig config = const StreamConfig(),
    Scheduler scheduler = const TimerScheduler(),
    double Function()? random,
    String Function()? sessionId,
  }) : _credentials = credentials,
       _config = config,
       _transports = transports,
       _scheduler = scheduler,
       _sessionId = (sessionId ?? _randomUuid)() {
    _controller = ReconnectController(
      onRemount: _beginAttempt,
      onSnapshot: _onSnapshot,
      onHeal: () => _credentialsStale = true,
      scheduler: scheduler,
      random: random,
    );
  }

  final StreamCredentialsProvider _credentials;
  final StreamConfig _config;
  final StreamTransports _transports;
  final Scheduler _scheduler;
  final String _sessionId;
  late final ReconnectController _controller;

  final ValueNotifier<StreamStatus> _status = ValueNotifier(
    const StreamConnecting(),
  );
  final ValueNotifier<VideoSize?> _videoSize = ValueNotifier(null);
  final ValueNotifier<MediaStream?> _videoStream = ValueNotifier(null);

  bool _started = false;
  bool _closed = false;
  StreamCredentials? _lastCredentials;
  bool _credentialsStale = true;
  _Attempt? _attempt;

  /// The connection status. Starts as [StreamConnecting].
  ValueListenable<StreamStatus> get status => _status;

  /// The size of the decoded video, null until the first frame.
  ValueListenable<VideoSize?> get videoSize => _videoSize;

  /// The stream carrying the device video, for a renderer. Null while there is
  /// no live connection; it changes on every reconnect.
  ValueListenable<MediaStream?> get videoStream => _videoStream;

  /// Starts connecting. A no-op when already started or closed.
  void start() {
    if (_started || _closed) return;
    _started = true;
    _beginAttempt();
  }

  /// Starts a fresh connect cycle after the stream became
  /// [StreamUnavailable]. A no-op in every other status.
  void retry() {
    if (_closed) return;
    _controller.retry();
  }

  /// Closes the session and releases the peer connection, streams, channels,
  /// socket and timers. The session cannot be used again.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _controller.dispose();
    final attempt = _attempt;
    _attempt = null;
    _videoStream.value = null;
    _videoSize.value = null;
    if (attempt != null) await attempt.dispose();
  }

  /// Sends a binary control message on the control channel. Returns whether it
  /// was sent: it is dropped while the channel is not open.
  bool sendControl(Uint8List data) => _sendOn(_attempt?.peer?.control, data);

  /// Sends a binary hover message on the hover channel only, never on the
  /// control channel. Returns whether it was sent: it is dropped while the
  /// hover channel is not open.
  bool sendHover(Uint8List data) => _sendOn(_attempt?.peer?.hover, data);

  bool _sendOn(DataChannelTransport? channel, Uint8List data) {
    if (_closed || channel == null || channel.state != ChannelState.open) {
      return false;
    }
    try {
      channel.send(data);
      return true;
    } on Object {
      return false;
    }
  }

  /// Asks the device to open [url]. Returns whether the request was sent: it
  /// is dropped while the signalling socket is not open.
  bool openUrl(String url) {
    final attempt = _liveAttempt;
    if (attempt == null || attempt.connection == null) return false;
    return _send(
      attempt,
      OpenUrlMessage.fromInput(input: url, sessionId: _sessionId),
    );
  }

  /// Takes a screenshot of the device and returns the image bytes (PNG).
  ///
  /// Throws a [TimeoutException] when the device does not answer within
  /// [timeout] and a [StreamSessionException] when the request cannot be sent,
  /// the device reports an error or the connection is lost meanwhile.
  Future<Uint8List> screenshot({
    Duration timeout = SignallingTiming.screenshotTimeout,
  }) {
    final attempt = _liveAttempt;
    if (attempt == null || attempt.connection == null) {
      return Future.error(
        const StreamSessionException('stream is not connected'),
      );
    }
    final id =
        'ui-ss-${DateTime.now().millisecondsSinceEpoch}-'
        '${math.Random().nextInt(1 << 32).toRadixString(36)}';
    final completer = Completer<Uint8List>();
    final pending = _PendingScreenshot(completer);
    attempt.screenshots[id] = pending;
    pending.timer = _scheduler.schedule(timeout, () {
      if (attempt.screenshots.remove(id) == null) return;
      completer.completeError(
        TimeoutException('screenshot request timed out', timeout),
      );
    });
    if (!_send(attempt, ScreenshotRequestMessage(id: id))) {
      attempt.screenshots.remove(id)?.timer?.cancel();
      return Future.error(
        const StreamSessionException('could not send screenshot request'),
      );
    }
    return completer.future;
  }

  // ---- attempt lifecycle -------------------------------------------------

  _Attempt? get _liveAttempt {
    final attempt = _attempt;
    return !_closed && attempt != null && attempt.live ? attempt : null;
  }

  void _onSnapshot(ReconnectSnapshot snapshot) {
    _status.value = switch (snapshot.status) {
      ReconnectStatus.connecting => const StreamConnecting(),
      ReconnectStatus.connected => const StreamConnected(),
      ReconnectStatus.reconnecting => StreamReconnecting(snapshot.attempt),
      ReconnectStatus.unavailable => const StreamUnavailable(),
    };
  }

  /// A new mount epoch: the previous attempt (if any) is torn down, a fresh
  /// one starts and the connect watchdog is armed.
  void _beginAttempt() {
    if (_closed) return;
    final previous = _attempt;
    if (previous != null) unawaited(previous.dispose());
    _videoStream.value = null;
    _videoSize.value = null;
    final attempt = _Attempt();
    _attempt = attempt;
    // The keepAlive timer is armed at mount, ticks are skipped unless the
    // socket is open.
    _scheduleKeepAlive(attempt);
    _controller.attemptMounted();
    unawaited(_run(attempt));
  }

  void _scheduleKeepAlive(_Attempt attempt) {
    attempt.keepAlive = _scheduler.schedule(
      SignallingTiming.keepAliveInterval,
      () {
        if (!attempt.live) return;
        if (attempt.connection != null) {
          _send(attempt, KeepAliveMessage(sessionId: _sessionId));
        }
        _scheduleKeepAlive(attempt);
      },
    );
  }

  bool _send(_Attempt attempt, ClientMessage message) {
    final connection = attempt.connection;
    if (!attempt.live || connection == null) return false;
    try {
      connection.send(message.encode());
      return true;
    } on Object {
      return false;
    }
  }

  /// A terminal failure of [attempt]: release it and hand over to the
  /// reconnect controller.
  void _fail(_Attempt attempt) {
    if (!attempt.live || _closed) return;
    unawaited(attempt.dispose());
    if (identical(_attempt, attempt)) {
      _videoStream.value = null;
      _videoSize.value = null;
    }
    _controller.handleFailure();
  }

  Future<StreamCredentials?> _resolveCredentials() async {
    if (_lastCredentials == null || _credentialsStale) {
      _credentialsStale = false;
      _lastCredentials = await _credentials();
      if (_lastCredentials == null) _credentialsStale = true;
    }
    return _lastCredentials;
  }

  Future<T> _within<T>(
    _Attempt attempt,
    Future<T> future,
    Duration timeout,
    String what,
  ) {
    final completer = Completer<T>();
    final timer = _scheduler.schedule(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException(what, timeout));
      }
    });
    attempt.timers.add(timer);
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

  /// One connect attempt, the counterpart of `start()` in
  /// `use-webrtc-connection.ts`.
  Future<void> _run(_Attempt attempt) async {
    try {
      final credentials = await _resolveCredentials();
      if (!attempt.live) return;
      if (credentials == null) {
        throw const StreamSessionException('credentials not ready');
      }

      final connectFuture = _transports.signalling.connect(
        credentials.toWebSocketUri(),
      );
      // A connection that opens after the attempt was given up on is closed.
      unawaited(
        connectFuture.then<void>((connection) {
          if (!attempt.live) unawaited(connection.close());
        }, onError: (Object _) {}),
      );
      final connection = await _within(
        attempt,
        connectFuture,
        SignallingTiming.wsOpenTimeout,
        'WebSocket connection timeout',
      );
      if (!attempt.live) return;
      attempt.connection = connection;

      // The socket closing is terminal for the session on the server, even
      // while the peer connection still reports connected.
      attempt.socketSubscription = connection.messages.listen(
        (text) => _onMessage(attempt, text),
        onDone: () => _fail(attempt),
        onError: (Object _) {},
      );

      _send(attempt, RequestRtcConfigurationMessage(sessionId: _sessionId));
      attempt.rtcConfiguration = Completer<RtcConfigurationMessage>();
      final configuration = await _within(
        attempt,
        attempt.rtcConfiguration!.future,
        SignallingTiming.rtcConfigTimeout,
        'RTCConfiguration timeout',
      );
      if (!attempt.live) return;
      attempt.phase = SignallingPhase.active;

      final peer = await _transports.peers.create(
        configuration.rtcConfiguration,
        config: _config,
      );
      if (!attempt.live) {
        await peer.close();
        return;
      }
      attempt.peer = peer;
      _wirePeer(attempt, peer);

      final sdp = await peer.createLocalOffer();
      if (!attempt.live) return;
      _send(attempt, OfferMessage(sdp: sdp, sessionId: _sessionId));
    } on Object catch (error) {
      if (!attempt.live) return;
      if (error is SignallingRejectedException && error.isUnauthorized) {
        // The token is stale: ask for new credentials on the next attempt.
        _credentialsStale = true;
      }
      _fail(attempt);
    }
  }

  void _wirePeer(_Attempt attempt, PeerTransport peer) {
    attempt.subscriptions
      ..add(peer.connectionStates.listen((s) => _onPeerState(attempt, s)))
      ..add(
        peer.localCandidates.listen((candidate) {
          _send(
            attempt,
            ClientCandidateMessage(
              candidate: candidate.candidate,
              sdpMid: candidate.sdpMid,
              sdpMLineIndex: candidate.sdpMLineIndex,
              sessionId: _sessionId,
            ),
          );
        }),
      )
      ..add(
        peer.remoteVideoStreams.listen((stream) {
          if (!attempt.live) return;
          _videoStream.value = stream;
          _pollVideoSize(attempt);
        }),
      )
      ..add(
        peer.control.states.listen((state) {
          if (state == ChannelState.open) _onControlOpen(attempt);
        }),
      );
  }

  /// The control channel opened: request the first frames.
  void _onControlOpen(_Attempt attempt) {
    if (!attempt.live || attempt.requestedFrames) return;
    attempt.requestedFrames = true;
    for (var i = 0; i < SignallingTiming.requestFrameCount; i++) {
      attempt.timers.add(
        _scheduler.schedule(SignallingTiming.requestFrameInterval * i, () {
          if (attempt.live) {
            _send(attempt, RequestFrameMessage(sessionId: _sessionId));
          }
        }),
      );
    }
  }

  static const Duration _videoSizeInterval = Duration(milliseconds: 500);

  void _pollVideoSize(_Attempt attempt) {
    attempt.sizePoll?.cancel();
    attempt.sizePoll = _scheduler.schedule(
      attempt.polledSize ? _videoSizeInterval : Duration.zero,
      () async {
        final peer = attempt.peer;
        if (!attempt.live || peer == null) return;
        try {
          final size = await peer.readVideoSize();
          if (attempt.live && size != null && size != _videoSize.value) {
            _videoSize.value = size;
          }
        } on Object {
          // A failed stats read is retried on the next tick.
        }
        if (!attempt.live) return;
        attempt.polledSize = true;
        _pollVideoSize(attempt);
      },
    );
  }

  // ---- peer connection state ---------------------------------------------

  void _onPeerState(_Attempt attempt, PeerState state) {
    if (!attempt.live) return;
    attempt.peerState = state;
    if (state == PeerState.failed || state == PeerState.closed) {
      // Terminal: this peer connection will not come back on its own.
      _fail(attempt);
      return;
    }
    if (state == PeerState.connected) {
      attempt.endGrace();
    } else if (attempt.inGrace) {
      // Media keeps flowing on the old candidate pair while a credential
      // refresh restarts ICE: a transient dip is not a disconnect. The check
      // at the end of the grace window reports one that outlived it.
      attempt.suppressedDip = true;
      return;
    }
    if (state == PeerState.connected) {
      _controller.handleConnected();
    } else {
      _controller.handleDisconnected();
    }
  }

  void _startGrace(_Attempt attempt) {
    attempt.endGrace();
    attempt.inGrace = true;
    attempt.graceTimer = _scheduler.schedule(
      SignallingTiming.iceRestartGrace,
      () {
        attempt.graceTimer = null;
        attempt.inGrace = false;
        if (!attempt.live) return;
        if (attempt.suppressedDip && attempt.peerState != PeerState.connected) {
          _controller.handleDisconnected();
        }
        attempt.suppressedDip = false;
      },
    );
  }

  // ---- signalling messages -----------------------------------------------

  void _onMessage(_Attempt attempt, String text) {
    if (!attempt.live) return;
    final ServerMessage? message;
    try {
      message = decodeServerMessage(text, phase: attempt.phase);
    } on SignallingStartupException {
      _fail(attempt);
      return;
    }
    if (message == null) return;
    switch (message) {
      case RtcConfigurationMessage():
        final pendingConfiguration = attempt.rtcConfiguration;
        if (attempt.phase == SignallingPhase.awaitingRtcConfiguration) {
          if (pendingConfiguration != null &&
              !pendingConfiguration.isCompleted) {
            pendingConfiguration.complete(message);
          }
        } else {
          unawaited(_onRtcRefresh(attempt, message));
        }
      case AnswerMessage():
        unawaited(_onAnswer(attempt, message));
      case ServerCandidateMessage():
        unawaited(_onRemoteCandidate(attempt, message));
      case ScreenshotMessage():
        final pending = attempt.screenshots.remove(message.id);
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
        final pending = attempt.screenshots.remove(message.id);
        if (pending == null) return;
        pending.timer?.cancel();
        pending.completer.completeError(
          StreamSessionException(message.message),
        );
    }
  }

  Future<void> _onAnswer(_Attempt attempt, AnswerMessage message) async {
    final peer = attempt.peer;
    if (peer == null) return;
    try {
      await peer.setRemoteAnswer(message.sdp);
    } on Object {
      // A stale answer (for a superseded ICE restart) is ignored: the newer
      // offer gets its own answer.
      return;
    }
    if (!attempt.live) return;
    attempt.remoteDescriptionSet = true;
    final buffered = List.of(attempt.pendingCandidates);
    attempt.pendingCandidates.clear();
    for (final candidate in buffered) {
      if (!attempt.live) return;
      try {
        await peer.addRemoteCandidate(candidate);
      } on Object {
        // A candidate that does not apply is skipped.
      }
    }
  }

  Future<void> _onRemoteCandidate(
    _Attempt attempt,
    ServerCandidateMessage message,
  ) async {
    final peer = attempt.peer;
    if (peer == null) return;
    final candidate = IceCandidateData(
      candidate: message.candidate,
      sdpMid: message.sdpMid,
      sdpMLineIndex: message.sdpMLineIndex,
    );
    if (!attempt.remoteDescriptionSet) {
      attempt.pendingCandidates.add(candidate);
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
  Future<void> _onRtcRefresh(
    _Attempt attempt,
    RtcConfigurationMessage message,
  ) async {
    final peer = attempt.peer;
    if (peer == null) return;
    final iceServers = message.rtcConfiguration['iceServers'];
    if (iceServers == null) return;
    try {
      await peer.setIceServers(iceServers);
    } on Object {
      return;
    }
    if (!attempt.live) return;
    _startGrace(attempt);
    try {
      final sdp = await peer.createLocalOffer(iceRestart: true);
      if (!attempt.live) return;
      // New ICE generation: buffer incoming candidates until the restart
      // answer arrives, applying them against the old remote description
      // would reject them on ufrag mismatch.
      attempt.remoteDescriptionSet = false;
      attempt.pendingCandidates.clear();
      _send(attempt, OfferMessage(sdp: sdp, sessionId: _sessionId));
    } on Object {
      if (attempt.live) attempt.endGrace();
    }
  }

  static Uint8List _decodeDataUri(String dataUri) {
    final comma = dataUri.indexOf(',');
    return base64Decode(comma < 0 ? dataUri : dataUri.substring(comma + 1));
  }

  static String _randomUuid() {
    final random = math.Random.secure();
    String hex(int length) => List.generate(
      length,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }
}

final class _PendingScreenshot {
  _PendingScreenshot(this.completer);

  final Completer<Uint8List> completer;
  ScheduledTask? timer;
}

/// Everything one connect attempt owns. Disposing it releases all of it.
final class _Attempt {
  bool live = true;
  SignallingConnection? connection;
  StreamSubscription<String>? socketSubscription;
  PeerTransport? peer;
  final List<StreamSubscription<Object?>> subscriptions = [];
  final List<ScheduledTask> timers = [];
  ScheduledTask? keepAlive;
  ScheduledTask? sizePoll;
  ScheduledTask? graceTimer;
  bool polledSize = false;
  bool requestedFrames = false;

  SignallingPhase phase = SignallingPhase.awaitingRtcConfiguration;
  Completer<RtcConfigurationMessage>? rtcConfiguration;

  // ICE buffering of the current ICE generation.
  bool remoteDescriptionSet = false;
  final List<IceCandidateData> pendingCandidates = [];

  PeerState peerState = PeerState.initial;
  bool inGrace = false;
  bool suppressedDip = false;

  final Map<String, _PendingScreenshot> screenshots = {};

  void endGrace() {
    graceTimer?.cancel();
    graceTimer = null;
    inGrace = false;
    suppressedDip = false;
  }

  Future<void> dispose() async {
    if (!live) return;
    live = false;
    keepAlive?.cancel();
    sizePoll?.cancel();
    graceTimer?.cancel();
    for (final timer in timers) {
      timer.cancel();
    }
    timers.clear();
    for (final pending in screenshots.values) {
      pending.timer?.cancel();
      pending.completer.completeError(
        const StreamSessionException('connection lost'),
      );
    }
    screenshots.clear();
    // Listeners go first so that closing never reports a failure.
    final socketSubscription = this.socketSubscription;
    this.socketSubscription = null;
    await socketSubscription?.cancel();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    final connection = this.connection;
    final peer = this.peer;
    await connection?.close();
    await peer?.close();
  }
}
