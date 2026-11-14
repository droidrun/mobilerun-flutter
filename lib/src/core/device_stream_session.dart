// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show MediaStream;

import '../protocol/stream_timing.dart';
import '../webrtc/default_transports.dart';
import 'reconnect_controller.dart';
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
  }) : this.withTransports(
         credentials: credentials,
         config: config,
         transports: defaultStreamTransports(),
       );

  /// Creates a session on custom transports and clock, for tests and debug
  /// tooling that wraps the default transports.
  @internal
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
       _sessionId = (sessionId ?? _randomUuid)(),
       _muted = config.muted {
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
  bool _muted;
  StreamCredentials? _lastCredentials;
  bool _credentialsStale = true;
  StreamAttempt? _attempt;
  int _attemptEpoch = 0;
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
    _beginAttempt();
  }

  /// Starts a fresh connect cycle after the stream became
  /// [StreamUnavailable]. A no-op in every other status.
  void retry() {
    if (_closed) return;
    _controller.retry();
  }

  /// Wakes a pending reconnect wait or restarts an unavailable session.
  /// Call this when the app's existing connectivity source comes back online.
  void wake() {
    if (_closed || !_started) return;
    _controller.handleWake();
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
    _attemptEpoch++;
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
    if (snapshot.status == ReconnectStatus.unavailable) {
      // The retry budget is spent: nothing of the last attempt may linger, a
      // late peer state must not bring the stream back without retry().
      unawaited(_attempt?.dispose());
      _clearVideo();
    }
  }

  Future<StreamCredentials?> _resolveCredentials(int epoch) async {
    if (_lastCredentials == null || _credentialsStale) {
      final next = await _credentials();
      if (_closed || epoch != _attemptEpoch) return null;
      _lastCredentials = next;
      _credentialsStale = next == null;
    }
    return _lastCredentials;
  }

  /// A new mount epoch: the previous attempt (if any) is torn down, a fresh
  /// one starts and the connect watchdog is armed.
  void _beginAttempt() {
    if (_closed) return;
    final epoch = ++_attemptEpoch;
    _credentialsPoll?.cancel();
    _credentialsPoll = null;
    unawaited(_attempt?.dispose());
    _attempt = null;
    _clearVideo();
    unawaited(_prepareAttempt(epoch));
  }

  Future<void> _prepareAttempt(int epoch) async {
    final StreamCredentials? resolved;
    try {
      resolved = await _resolveCredentials(epoch);
    } on Object {
      if (_closed || epoch != _attemptEpoch) return;
      _credentialsStale = true;
      _controller.attemptMounted();
      _controller.handleFailure();
      return;
    }
    if (_closed || epoch != _attemptEpoch) return;
    if (resolved == null) {
      // Waiting for a device to become ready is not a stream failure. One
      // owner polls indefinitely without consuming the reconnect budget.
      _credentialsPoll = _scheduler.schedule(const Duration(seconds: 3), () {
        _credentialsPoll = null;
        unawaited(_prepareAttempt(epoch));
      });
      return;
    }
    _controller.attemptMounted();
    _attempt = StreamAttempt(
      sessionId: _sessionId,
      transports: _transports,
      scheduler: _scheduler,
      config: _config,
      muted: _muted,
      credentials: () async => resolved,
      events: StreamAttemptEvents(
        connected: _controller.handleConnected,
        disconnected: _controller.handleDisconnected,
        failed: () {
          _clearVideo();
          _controller.handleFailure();
        },
        videoStream: (stream) => _videoStream.value = stream,
        videoSize: (size) => _videoSize.value = size,
        credentialsRejected: () => _credentialsStale = true,
      ),
    )..setVisible(_visible);
    _attempt!.start();
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
