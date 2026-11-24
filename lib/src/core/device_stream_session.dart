// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../webrtc/default_transports.dart';
import 'reconnect_controller.dart';
import 'publish.dart';
import 'publish_controller.dart';
import 'reconnect_policy.dart';
import 'scheduler.dart';
import 'stream_attempt.dart';
import 'stream_config.dart';
import 'stream_credentials.dart';
import 'stream_error.dart';
import 'stream_exception.dart';
import 'stream_status.dart';
import 'stream_stats.dart';
import 'stream_transports.dart';

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
  /// [StreamCredentialsProvider]. [onError] receives every failed attempt with
  /// a [StreamErrorReason]; see [StreamError]. A throwing callback is ignored.
  DeviceStreamSession({
    required StreamCredentialsProvider credentials,
    StreamConfig config = const StreamConfig(),
    StreamErrorCallback? onError,
  }) : this.withTransports(
         credentials: credentials,
         config: config,
         onError: onError,
         transports: defaultStreamTransports(),
       );

  /// Creates a session on custom transports and clock, for tests and debug
  /// tooling that wraps the default transports.
  @internal
  DeviceStreamSession.withTransports({
    required this._credentials,
    required this._transports,
    StreamConfig config = const StreamConfig(),
    this._onError,
    Scheduler scheduler = const TimerScheduler(),
    double Function()? random,
    String Function()? sessionId,
  }) : _config = config,
       _scheduler = scheduler,
       _sessionId = (sessionId ?? _randomUuid)(),
       _muted = config.muted {
    _publish = PublishController(
      capabilities: config.publishCapabilities,
      capture: _transports.publishCapture,
      scheduler: scheduler,
      uuid: _randomUuid,
      onFailure: (failure, id) {
        final error = StreamError(
          reason: failure.reason,
          message: failure.message,
          attempt: _controller.snapshot.attempt,
          isFinal: true,
          operation: 'publish',
          mediaSessionId: id,
          detail: failure.detail,
          serverReason: failure.serverReason,
        );
        try {
          _onError?.call(error);
        } on Object {
          debugPrint('[mobilerun.stream] onError threw');
        }
      },
    );
    _stats = _ObservedStats(_updateSampling);
    _controller = ReconnectController(
      onRemount: _beginAttempt,
      onSnapshot: _onSnapshot,
      onHeal: _requestCredentials,
      onFailure: _reportFailure,
      scheduler: scheduler,
      random: random,
    );
  }

  final StreamCredentialsProvider _credentials;
  final StreamConfig _config;
  final StreamErrorCallback? _onError;
  final StreamTransports _transports;
  final Scheduler _scheduler;
  final String _sessionId;
  late final ReconnectController _controller;
  late final PublishController _publish;

  final ValueNotifier<StreamStatus> _status = ValueNotifier(
    const StreamConnecting(),
  );
  late final _ObservedStats _stats;
  final ValueNotifier<VideoSize?> _videoSize = ValueNotifier(null);
  final ValueNotifier<StreamError?> _lastError = ValueNotifier(null);
  final ValueNotifier<MediaStream?> _videoStream = ValueNotifier(null);

  bool _started = false;
  bool get _closed => _closedState.value;
  final ValueNotifier<bool> _closedState = ValueNotifier(false);
  bool _muted;
  StreamCredentials? _lastCredentials;
  StreamCredentials? _activeCredentials;
  int _credentialsEpoch = 0;
  bool _credentialsPending = false;
  ScheduledTask? _credentialsTimeout;
  StreamAttempt? _attempt;
  StreamAttempt? _forcedAttempt;
  final _retiredDisposals = <Future<void>>{};
  ScheduledTask? _credentialsPoll;
  bool _visible = true;
  bool _networkAvailable = true;
  int _videoRotation = 0;
  String? _pendingUrl;
  bool _warnedStaticToken = false;

  // Set while the controller counts a failure whose cause the attempt knows.
  StreamErrorReason? _failureReason;
  String? _failureMessage;

  /// Whether this session has been closed, for the SDK views.
  @internal
  ValueListenable<bool> get closed => _closedState;

  /// Publication support supplied at session creation. It grants no permission.
  DevicePublishCapabilities? get publishCapabilities =>
      _config.publishCapabilities;

  /// Whether the local connection reserved a supported camera sender.
  @internal
  ValueListenable<bool> get publishCameraAvailable => _publish.cameraAvailable;

  /// Publication lifecycle, independent of the viewer connection status.
  ValueListenable<PublishState> get publishState => _publish.state;

  /// Captures local inputs on explicit user action, then requests admission.
  /// Resolves only after the server reports active and all tracks attach.
  /// Throws [PublishException] with a structured failure.
  Future<PublishState> startPublish(PublishOptions options) =>
      _publish.start(options);

  /// Releases local inputs and reserved senders without stopping the viewer.
  Future<void> stopPublish() => _publish.stop();

  /// The connection status. Starts as [StreamConnecting].
  ValueListenable<StreamStatus> get status => _status;

  /// The latest failed attempt of the current recovery cycle; null while
  /// connected and after a fresh cycle starts. Also delivered to `onError`.
  ValueListenable<StreamError?> get lastError => _lastError;

  /// Inbound video statistics sampled every second while connected.
  /// Null unless connected, visible and observed; unsupported fields stay null.
  ValueListenable<StreamStats?> get stats => _stats;

  /// The size of the decoded video, null until the first frame.
  ValueListenable<VideoSize?> get videoSize => _videoSize;

  /// The stream carrying the device video, for a renderer. Null while there is
  /// no live connection; it changes on every reconnect.
  @internal
  ValueListenable<MediaStream?> get videoStream => _videoStream;

  /// Updates the decoded rotation reported by the native renderer.
  @internal
  void updateVideoRotation(int rotation) {
    if (_closed) return;
    _videoRotation = rotation;
    final size = _videoSize.value;
    if (size == null || size.rotation == rotation) return;
    _videoSize.value = VideoSize(size.width, size.height, rotation: rotation);
  }

  /// Starts connecting. A no-op when already started or closed.
  void start() {
    if (_started || _closed) return;
    _started = true;
    if (!_networkAvailable) {
      _controller.setOfflineUnavailable();
      return;
    }
    _requestCredentials();
  }

  /// Starts a fresh connect cycle after the stream became
  /// [StreamUnavailable]. Before discovery, also restarts a pending provider call.
  /// An explicit Retry overrides an offline hint for one fresh attempt. While
  /// offline, Retry preserves connected media and an already-live forced attempt.
  void retry() {
    if (_closed || !_started) return;
    if (!_networkAvailable) {
      if (_status.value is StreamConnected ||
          (_forcedAttempt?.live ?? false) ||
          _credentialsPending) {
        return;
      }
      _controller.prepareOfflineRetry();
      if (_lastCredentials == null) {
        _requestCredentials(replacePending: true, allowOffline: true);
      } else {
        _beginAttempt(allowOffline: true);
      }
      return;
    }
    if (_lastCredentials == null) {
      _requestCredentials(replacePending: true);
    } else {
      _controller.retry();
    }
  }

  /// Wakes a pending reconnect wait or restarts an unavailable session.
  /// Network sources should use [setNetworkAvailable] to reset backoff too.
  void handleWake() {
    if (_closed || !_started) return;
    if (_lastCredentials == null) {
      _requestCredentials(replacePending: true);
    } else {
      _controller.handleWake();
    }
  }

  /// Supplies advisory route availability, optimistic until first observed.
  /// Offline suppresses automatic discovery and new sockets; healthy media stays alive.
  /// Network return restarts unavailable sessions, but retains a live forced
  /// attempt that already allocated its socket.
  void setNetworkAvailable(bool available) {
    if (_closed || _networkAvailable == available) return;
    _networkAvailable = available;
    if (!available) {
      _credentialsEpoch++;
      _credentialsPending = false;
      _credentialsTimeout?.cancel();
      _credentialsPoll?.cancel();
      if (_status.value is! StreamConnected) {
        _retireAttempt();
        _attempt = null;
        _activeCredentials = null;
        _clearVideo();
      }
    }
    _controller.setNetworkAvailable(
      available,
      preserveAttempt:
          (_forcedAttempt?.live ?? false) &&
          (_forcedAttempt?.socketAllocated ?? false),
    );
    if (!available && _started && _status.value is! StreamConnected) {
      _controller.setOfflineUnavailable();
    }
    if (available && _started && _lastCredentials == null) {
      _requestCredentials(replacePending: true);
    }
  }

  /// Pauses keepAlive while hidden; a real foreground transition also wakes
  /// reconnects. Registration with an already-visible app is a no-op.
  void setVisible(bool visible) {
    if (_closed || _visible == visible) return;
    _visible = visible;
    _attempt?.setVisible(visible);
    _updateSampling();
    if (visible) handleWake();
  }

  /// Closes the session and releases the peer connection, streams, channels,
  /// socket and timers. The session cannot be used again.
  Future<void> close() async {
    if (_closed) return;
    _closedState.value = true;
    final publishClose = _publish.close();
    _credentialsEpoch++;
    _pendingUrl = null;
    _credentialsTimeout?.cancel();
    _credentialsPoll?.cancel();
    _controller.dispose();
    final attempt = _attempt;
    _attempt = null;
    _forcedAttempt = null;
    _clearVideo();
    await publishClose;
    await attempt?.dispose();
    await Future.wait(_retiredDisposals.toList());
  }

  /// Mutes or unmutes the device audio, now and on later connections. The
  /// audio track stays negotiated either way. The initial value is
  /// [StreamConfig.muted].
  void setMuted(bool muted) {
    _muted = muted;
    _attempt?.setMuted(muted);
  }

  /// Sends a binary control message on the control channel. Returns whether it
  /// was sent: it is dropped while the channel is not open.
  @internal
  bool sendControl(Uint8List data) => _attempt?.sendControl(data) ?? false;

  /// Sends a binary hover message on the hover channel only, never on the
  /// control channel. Returns whether it was sent: it is dropped while the
  /// hover channel is not open.
  @internal
  bool sendHover(Uint8List data) => _attempt?.sendHover(data) ?? false;

  /// Asks the device to open [url]. Until the control channel opens, only the
  /// latest URL is queued.
  void openUrl(String url) {
    if (_closed) return;
    _pendingUrl = url;
    _flushUrl();
  }

  void _flushUrl() {
    final url = _pendingUrl;
    if (!_closed && url != null && (_attempt?.openUrl(url) ?? false)) {
      _pendingUrl = null;
    }
  }

  /// Takes a screenshot of the device and returns the image bytes (PNG).
  ///
  /// Throws a [ScreenshotTimeoutException] when the device does not answer within
  /// [timeout], [StreamNotConnectedException] when the request cannot be sent,
  /// [ScreenshotFailedException] when the device reports an error, or
  /// [StreamDisconnectedException] when the connection is lost meanwhile.
  Future<Uint8List> screenshot({
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _attempt?.screenshot(timeout) ??
      Future.error(const StreamNotConnectedException());

  // ---- attempt lifecycle --------------------------------------------------

  void _clearVideo() {
    _videoRotation = 0;
    _stats.value = null;
    _videoStream.value = null;
    _videoSize.value = null;
  }

  void _onSnapshot(ReconnectSnapshot snapshot) {
    _status.value = switch (snapshot.status) {
      ReconnectStatus.connecting => const StreamConnecting(),
      ReconnectStatus.connected => const StreamConnected(),
      ReconnectStatus.reconnecting => StreamReconnecting(snapshot.attempt),
      ReconnectStatus.unavailable => const StreamUnavailable(),
    };
    if (snapshot.status == ReconnectStatus.connected ||
        (snapshot.status == ReconnectStatus.reconnecting &&
            snapshot.attempt == 0)) {
      _lastError.value = null;
    }
    _updateSampling();
    scheduleMicrotask(_applyPendingTarget);
    if (snapshot.status == ReconnectStatus.unavailable) {
      // Automatic retrying stopped: no late peer state may revive the attempt.
      _retireAttempt();
      _clearVideo();
    }
  }

  void _withFailure(
    StreamErrorReason reason,
    String message,
    void Function() count,
  ) {
    _failureReason = reason;
    _failureMessage = message;
    try {
      count();
    } finally {
      _failureReason = null;
      _failureMessage = null;
    }
  }

  void _reportFailure(int attempt, bool isFinal) {
    final error = StreamError(
      // No attempt signal: the connect watchdog expired.
      reason: _failureReason ?? StreamErrorReason.unknown,
      message: _failureMessage ?? 'Connection attempt timed out',
      attempt: attempt,
      isFinal: isFinal,
    );
    _lastError.value = error;
    final onError = _onError;
    if (onError == null) return;
    try {
      onError(error);
    } on Object catch (error) {
      debugPrint('[mobilerun.stream] onError threw: ${error.runtimeType}');
    }
  }

  // Legacy exception: a reconnect reuses the static token; single-use stream tokens fail.
  void _warnStaticToken(StreamCredentials credentials) {
    final token = credentials.token;
    if (_warnedStaticToken ||
        credentials.tokenProvider != null ||
        token == null ||
        token.isEmpty) {
      return;
    }
    _warnedStaticToken = true;
    debugPrint(
      '[mobilerun.stream] StreamCredentials.token is deprecated '
      '(device token (legacy)): reconnects '
      'reuse it, which fails for single-use stream tokens. Use '
      'StreamCredentials.tokenProvider.',
    );
  }

  void _updateSampling() {
    final enabled =
        !_closed &&
        _visible &&
        _stats.observed &&
        _status.value is StreamConnected;
    _attempt?.setStatsEnabled(enabled);
    if (!enabled) _stats.value = null;
  }

  // Only initial discovery polls. Recovery mounts always use the latest cached
  // target; a bounded background refresh must never stall reconnect progress.
  void _requestCredentials({
    bool replacePending = false,
    bool allowOffline = false,
  }) {
    if (_closed ||
        (!_networkAvailable && !allowOffline) ||
        (_credentialsPending && !replacePending)) {
      return;
    }
    final epoch = ++_credentialsEpoch;
    _credentialsPending = true;
    _credentialsPoll?.cancel();
    _credentialsTimeout?.cancel();
    void finish(StreamCredentials? next) {
      if (_closed || epoch != _credentialsEpoch || !_credentialsPending) return;
      _credentialsPending = false;
      _credentialsTimeout?.cancel();
      _credentialsTimeout = null;
      if (next == null) {
        if (!_networkAvailable) {
          _controller.setOfflineUnavailable();
        } else if (_lastCredentials == null) {
          _credentialsPoll = _scheduler.schedule(
            const Duration(seconds: 3),
            () {
              _credentialsPoll = null;
              _requestCredentials();
            },
          );
        }
        return;
      }
      _lastCredentials = next;
      if (allowOffline) {
        _beginAttempt(allowOffline: true);
      } else {
        _applyPendingTarget();
      }
    }

    _credentialsTimeout = _scheduler.schedule(
      InternalReconnectPolicy.connectTimeout,
      () => finish(null),
    );
    unawaited(
      Future<StreamCredentials?>.sync(_credentials)
          .then(finish, onError: (Object _) => finish(null)),
    );
  }

  void _applyPendingTarget() {
    final next = _lastCredentials;
    if (_closed || next == null || _controller.shouldDeferTargetChange()) {
      return;
    }
    if (_activeCredentials?.url != next.url ||
        (_status.value is! StreamConnected &&
            _activeCredentials?.token != next.token)) {
      _beginAttempt();
    }
  }

  void _retireAttempt() {
    final retired = _attempt;
    if (retired == null) return;
    final disposal = retired.dispose();
    _retiredDisposals.add(disposal);
    unawaited(disposal.whenComplete(() => _retiredDisposals.remove(disposal)));
  }

  /// Tears down the previous connection and mounts the cached target.
  void _beginAttempt({bool allowOffline = false}) {
    final resolved = _lastCredentials;
    if (_closed || (!_networkAvailable && !allowOffline) || resolved == null) {
      return;
    }
    _retireAttempt();
    _clearVideo();
    _activeCredentials = resolved;
    _warnStaticToken(resolved);
    _controller.attemptMounted(startWatchdog: false);
    final attempt = StreamAttempt(
      sessionId: _sessionId,
      publisher: _publish,
      transports: _transports,
      scheduler: _scheduler,
      config: _config,
      muted: _muted,
      credentials: resolved,
      visible: _visible,
      events: StreamAttemptEvents(
        socketAllocated: _controller.attemptMounted,
        controlReady: _flushUrl,
        stats: (sample) =>
            _stats.value = _status.value is StreamConnected ? sample : null,
        connected: _controller.handleConnected,
        disconnected: () => _withFailure(
          StreamErrorReason.disconnected,
          'Peer connection dropped',
          _controller.handleDisconnected,
        ),
        failed: (reason, message) {
          _clearVideo();
          _withFailure(reason, message, _controller.handleFailure);
        },
        videoStream: (stream) => _videoStream.value = stream,
        videoSize: (size) => _videoSize.value = VideoSize(
          size.width,
          size.height,
          rotation: _videoRotation,
        ),
        credentialsRejected: _requestCredentials,
      ),
    );
    _attempt = attempt;
    _forcedAttempt = allowOffline ? attempt : null;
    attempt.start();
    _updateSampling();
  }

  static String _randomUuid() {
    final random = Random.secure();
    String hex(int length) => List.generate(
      length,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }
}

// Eligibility follows observer changes without adding a public notifier API.
final class _ObservedStats extends ValueNotifier<StreamStats?> {
  _ObservedStats(this.changed) : super(null);
  final VoidCallback changed;
  bool get observed => hasListeners;

  @override
  void addListener(VoidCallback listener) {
    final before = hasListeners;
    super.addListener(listener);
    if (!before) changed();
  }

  @override
  void removeListener(VoidCallback listener) {
    final before = hasListeners;
    super.removeListener(listener);
    if (before && !hasListeners) changed();
  }
}
