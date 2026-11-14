// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../protocol/stream_timing.dart';
import '../webrtc/default_transports.dart';
import 'reconnect_controller.dart';
import 'reconnect_policy.dart';
import 'scheduler.dart';
import 'stream_attempt.dart';
import 'stream_config.dart';
import 'stream_credentials.dart';
import 'stream_exception.dart';
import 'stream_status.dart';
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
  /// [StreamCredentialsProvider].
  DeviceStreamSession({
    required StreamCredentialsProvider credentials,
    StreamConfig config = const StreamConfig(),
  }) : this._withTransports(
         credentials: credentials,
         config: config,
         transports: defaultStreamTransports(),
       );

  /// Creates a session on custom transports and clock, for tests and debug
  /// tooling that wraps the default transports.
  @internal
  DeviceStreamSession._withTransports({
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
       _sessionId = (sessionId ?? _randomUuid)(),
       _muted = config.muted {
    _controller = ReconnectController(
      onRemount: _beginAttempt,
      onSnapshot: _onSnapshot,
      onHeal: _requestCredentials,
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
  bool _muted;
  StreamCredentials? _lastCredentials;
  StreamCredentials? _activeCredentials;
  int _credentialsEpoch = 0;
  bool _credentialsPending = false;
  ScheduledTask? _credentialsTimeout;
  StreamAttempt? _attempt;
  ScheduledTask? _credentialsPoll;
  bool _visible = true;

  /// The connection status. Starts as [StreamConnecting].
  ValueListenable<StreamStatus> get status => _status;

  /// The size of the decoded video, null until the first frame.
  ValueListenable<VideoSize?> get videoSize => _videoSize;

  /// The stream carrying the device video, for a renderer. Null while there is
  /// no live connection; it changes on every reconnect.
  @internal
  ValueListenable<MediaStream?> get videoStream => _videoStream;

  /// Starts connecting. A no-op when already started or closed.
  void start() {
    if (_started || _closed) return;
    _started = true;
    _requestCredentials();
  }

  /// Starts a fresh connect cycle after the stream became
  /// [StreamUnavailable]. Before discovery, also restarts a pending provider call.
  void retry() {
    if (_closed || !_started) return;
    if (_lastCredentials == null) {
      _requestCredentials(replacePending: true);
    } else {
      _controller.retry();
    }
  }

  /// Wakes a pending reconnect wait or restarts an unavailable session.
  /// Call this when the app's existing connectivity source comes back online.
  void wake() {
    if (_closed || !_started) return;
    if (_lastCredentials == null) {
      _requestCredentials(replacePending: true);
    } else {
      _controller.handleWake();
    }
  }

  /// Pauses keepAlive while hidden; a real foreground transition also wakes
  /// reconnects. Registration with an already-visible app is a no-op.
  void setVisible(bool visible) {
    if (_closed || _visible == visible) return;
    _visible = visible;
    _attempt?.setVisible(visible);
    if (visible) wake();
  }

  /// Closes the session and releases the peer connection, streams, channels,
  /// socket and timers. The session cannot be used again.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _credentialsEpoch++;
    _credentialsTimeout?.cancel();
    _credentialsPoll?.cancel();
    _controller.dispose();
    final attempt = _attempt;
    _attempt = null;
    _clearVideo();
    await attempt?.dispose();
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

  /// Asks the device to open [url]. Returns whether the request was sent: it
  /// is dropped while the signalling socket is not open.
  bool openUrl(String url) => _attempt?.openUrl(url) ?? false;

  /// Takes a screenshot of the device and returns the image bytes (PNG).
  ///
  /// Throws a [TimeoutException] when the device does not answer within
  /// [timeout] and a [StreamSessionException] when the request cannot be sent,
  /// the device reports an error or the connection is lost meanwhile.
  Future<Uint8List> screenshot({
    Duration timeout = SignallingTiming.screenshotTimeout,
  }) =>
      _attempt?.screenshot(timeout) ??
      Future.error(const StreamSessionException('stream is not connected'));

  // ---- attempt lifecycle --------------------------------------------------

  void _clearVideo() {
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
    scheduleMicrotask(_applyPendingTarget);
    if (snapshot.status == ReconnectStatus.unavailable) {
      // The retry budget is spent: nothing of the last attempt may linger, a
      // late peer state must not bring the stream back without retry().
      unawaited(_attempt?.dispose());
      _clearVideo();
    }
  }

  // Only initial discovery polls. Recovery mounts always use the latest cached
  // target; a bounded background refresh must never stall reconnect progress.
  void _requestCredentials({bool replacePending = false}) {
    if (_closed || (_credentialsPending && !replacePending)) return;
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
        if (_lastCredentials == null) {
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
      _applyPendingTarget();
    }

    _credentialsTimeout = _scheduler.schedule(
      ReconnectPolicy.connectTimeout,
      () => finish(null),
    );
    unawaited(
      Future<StreamCredentials?>.sync(
        _credentials,
      ).then(finish, onError: (Object _) => finish(null)),
    );
  }

  void _applyPendingTarget() {
    final next = _lastCredentials;
    if (_closed || next == null || _controller.shouldDeferTargetChange()) {
      return;
    }
    if (_activeCredentials?.url != next.url ||
        _activeCredentials?.token != next.token) {
      _beginAttempt();
    }
  }

  /// Tears down the previous connection and mounts the cached target.
  void _beginAttempt() {
    final resolved = _lastCredentials;
    if (_closed || resolved == null) return;
    unawaited(_attempt?.dispose());
    _clearVideo();
    _activeCredentials = resolved;
    _controller.attemptMounted();
    _attempt = StreamAttempt(
      sessionId: _sessionId,
      transports: _transports,
      scheduler: _scheduler,
      config: _config,
      muted: _muted,
      credentials: resolved,
      visible: _visible,
      events: StreamAttemptEvents(
        connected: _controller.handleConnected,
        disconnected: _controller.handleDisconnected,
        failed: () {
          _clearVideo();
          _controller.handleFailure();
        },
        videoStream: (stream) => _videoStream.value = stream,
        videoSize: (size) => _videoSize.value = size,
        credentialsRejected: _requestCredentials,
      ),
    )..start();
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

/// Creates sessions with injected transports for tests and diagnostic examples.
/// This internal hook is intentionally absent from the package entry point.
@internal
DeviceStreamSession createDeviceStreamSessionWithTransports({
  required StreamCredentialsProvider credentials,
  required StreamTransports transports,
  StreamConfig config = const StreamConfig(),
  Scheduler scheduler = const TimerScheduler(),
  double Function()? random,
  String Function()? sessionId,
}) => DeviceStreamSession._withTransports(
  credentials: credentials,
  transports: transports,
  config: config,
  scheduler: scheduler,
  random: random,
  sessionId: sessionId,
);
