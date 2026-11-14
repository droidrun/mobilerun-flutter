// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'debug_signalling.dart';

/// Drives one session through the checks of the connection slice and logs
/// `E2E` lines for the host script. Device screenshots are written to
/// [outDir]; the host script screenshots the emulator whenever [hostShot]
/// prints its marker, and checks the pixels there.
final class E2eScript {
  E2eScript({
    required this.session,
    required this.debug,
    required this.outDir,
    required this.hostShot,
  });

  final DeviceStreamSession session;
  final DebugTransports debug;
  final Directory outDir;

  /// Asks the host to screenshot the emulator and waits for it.
  final Future<void> Function(String name) hostShot;

  void _log(String message) => debugPrint('E2E $message');

  Never _fail(String message) => throw StateError(message);

  Future<void> _sleep(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> _until(
    bool Function() condition,
    String what, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        _fail('timed out waiting for $what');
      }
      await _sleep(100);
    }
  }

  bool get _connected => session.status.value is StreamConnected;

  Future<void> _deviceShot(String name) async {
    final bytes = await session.screenshot();
    outDir.createSync(recursive: true);
    File('${outDir.path}/$name.png').writeAsBytesSync(bytes);
    _log('device-shot $name bytes=${bytes.length}');
  }

  // The Settings icon of the cloud phone's home screen, in a 488x1080 frame.
  Future<void> _tapSettings() async {
    final size = session.videoSize.value ?? _fail('no video size');
    final x = 73 * size.width / 488;
    final y = 966 * size.height / 1080;
    Uint8List touch(int action) => encodeTouch(
      action: action,
      pointerId: 0,
      videoWidth: size.width,
      videoHeight: size.height,
      x: x,
      y: y,
      actionButton: 1,
      buttons: action == AndroidMotionEvent.actionUp ? 0 : 1,
    );
    final down = session.sendControl(touch(AndroidMotionEvent.actionDown));
    await _sleep(80);
    final up = session.sendControl(touch(AndroidMotionEvent.actionUp));
    _log('tap sent down=$down up=$up at ${x.round()},${y.round()}');
    if (!down || !up) _fail('tap was not sent');
  }

  Future<void> _home() async {
    for (final action in [AndroidKeys.actionDown, AndroidKeys.actionUp]) {
      session.sendControl(
        encodeKeycode(action: action, keycode: AndroidKeys.keycodeHome),
      );
    }
    _log('home key sent');
  }

  Future<void> _awaitVideo(String what) async {
    await _until(() => _connected, '$what: connected');
    await _until(() => session.videoSize.value != null, '$what: video size');
    _log('$what connected video=${session.videoSize.value}');
  }

  /// The credential refresh: a changed local ICE ufrag in the restart offer, an
  /// answer to it, and frames flowing for 16 s without leaving connected.
  Future<void> _checkRefresh() async {
    final offersBefore = debug.offerUfrags.length;
    final answersBefore = debug.received.where((t) => t == 'answer').length;
    final framesBefore = await debug.framesDecoded() ?? 0;
    if (!debug.injectRefresh()) _fail('no rtcConfiguration to replay');
    await _until(
      () => debug.offerUfrags.length > offersBefore,
      'the ICE-restart offer',
      timeout: const Duration(seconds: 10),
    );
    final ufrags = debug.offerUfrags;
    _log(
      'refresh ufrag ${ufrags[offersBefore - 1]} -> ${ufrags[offersBefore]}',
    );
    if (ufrags[offersBefore] == ufrags[offersBefore - 1]) {
      _fail('the restart offer kept the ICE ufrag');
    }
    await _until(
      () => debug.received.where((t) => t == 'answer').length > answersBefore,
      'the answer to the restart offer',
      timeout: const Duration(seconds: 10),
    );
    _log('refresh answer received');
    for (var i = 0; i < 32; i++) {
      await _sleep(500);
      if (!_connected) {
        _fail('left connected during the refresh: ${session.status.value}');
      }
    }
    final framesAfter = await debug.framesDecoded() ?? 0;
    _log('refresh frames $framesBefore -> $framesAfter over 16 s');
    if (framesAfter - framesBefore < 160) {
      _fail('frames did not continue after the refresh');
    }
  }

  Future<void> run() async {
    _log('START');
    final stopwatch = Stopwatch()..start();
    session.start();
    await _awaitVideo('first');
    _log('first connected after ${stopwatch.elapsedMilliseconds} ms');
    await _sleep(3000);
    final counts = <String, int>{};
    for (final type in debug.sent) {
      counts[type] = (counts[type] ?? 0) + 1;
    }
    _log('sent frames $counts');
    await hostShot('01-first-frame');

    // Raw control bytes: HOME key, then a tap on the Settings icon.
    await _home();
    await _sleep(2500);
    await _deviceShot('02-before-tap');
    await hostShot('02-before-tap');
    await _tapSettings();
    await _sleep(3500);
    await _deviceShot('03-after-tap');
    await hostShot('03-after-tap');

    // Hover goes to its own channel; it must not disturb the control channel.
    final size = session.videoSize.value ?? _fail('no video size');
    final hover = session.sendHover(
      encodeHover(
        videoWidth: size.width,
        videoHeight: size.height,
        x: 100,
        y: 100,
      ),
    );
    _log('hover sent=$hover');

    // Forced WS close: full rebuild through the reconnect controller.
    final statuses = <String>[];
    void onStatus() => statuses.add('${session.status.value}');
    session.status.addListener(onStatus);
    debug.killSocket();
    _log('socket killed');
    await _until(
      () => session.status.value is StreamReconnecting,
      'reconnecting',
    );
    await hostShot('04-reconnecting');
    await _awaitVideo('rebuilt');
    await _sleep(2500);
    session.status.removeListener(onStatus);
    _log('after kill statuses=${statuses.join(' > ')}');
    await hostShot('05-after-reconnect');

    // Control works on the rebuilt session: HOME, then the tap again.
    await _home();
    await _sleep(2000);
    await _deviceShot('06-reconnected-home');
    await _tapSettings();
    await _sleep(3500);
    await _deviceShot('07-reconnected-after-tap');
    await hostShot('06-reconnected-after-tap');

    await _checkRefresh();
    await _deviceShot('08-after-refresh');
    await hostShot('07-after-refresh');

    await session.close();
  }
}
