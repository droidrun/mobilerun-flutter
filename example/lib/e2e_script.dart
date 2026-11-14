// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_signalling.dart';

/// Credentials of a scripted run, read at run time from a private file in the
/// app's support directory (`e2e.json`). They are never compiled in.
final class E2eConfig {
  const E2eConfig({required this.url, required this.token});

  final String url;
  final String token;

  /// The config file, or null when the app was started normally.
  static Future<E2eConfig?> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/e2e.json');
      if (!file.existsSync()) return null;
      final json = jsonDecode(await file.readAsString()) as Map;
      return E2eConfig(
        url: json['streamUrl']! as String,
        token: json['streamToken']! as String,
      );
    } on Object {
      return null;
    }
  }
}

/// Drives one session through the checks of the S2 slice and logs `E2E`
/// lines for the host script. Device screenshots are written to the app's
/// support directory, under `e2e-out/`.
final class E2eScript {
  E2eScript({
    required this.session,
    required this.signalling,
    required this.hostShot,
  });

  final DeviceStreamSession session;
  final DebugSignalling signalling;

  /// Asks the host to screenshot the emulator and waits for it.
  final Future<void> Function(String name) hostShot;

  void _log(String message) => debugPrint('E2E $message');

  Future<void> _until(
    bool Function() condition,
    String what, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('timed out waiting for $what');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _sleep(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> _deviceShot(String name) async {
    final bytes = await session.screenshot();
    final dir = await getApplicationSupportDirectory();
    final out = Directory('${dir.path}/e2e-out')..createSync(recursive: true);
    File('${out.path}/$name.png').writeAsBytesSync(bytes);
    _log('device-shot $name bytes=${bytes.length}');
  }

  // The Settings icon of the cloud phone's home screen, in a 488x1080 frame.
  Future<void> _tapSettings() async {
    final size = session.videoSize.value!;
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
    _log(
      'tap sent down=$down up=$up at ${x.round()},${y.round()} of ${size.width}x${size.height}',
    );
  }

  Future<void> _home() async {
    for (final action in [AndroidKeys.actionDown, AndroidKeys.actionUp]) {
      session.sendControl(
        encodeKeycode(action: action, keycode: AndroidKeys.keycodeHome),
      );
    }
    _log('home key sent');
  }

  bool get _connected => session.status.value is StreamConnected;

  Future<void> _awaitVideo(String what) async {
    await _until(() => _connected, '$what: connected');
    await _until(() => session.videoSize.value != null, '$what: video size');
    _log('$what connected video=${session.videoSize.value}');
  }

  Future<void> run() async {
    _log('START');
    final stopwatch = Stopwatch()..start();
    session.start();
    await _awaitVideo('first');
    _log('first frame after ${stopwatch.elapsedMilliseconds} ms');
    await _sleep(3000);
    final counts = <String, int>{};
    for (final type in signalling.sentTypes) {
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
    final hover = session.sendHover(
      encodeHover(
        videoWidth: session.videoSize.value!.width,
        videoHeight: session.videoSize.value!.height,
        x: 100,
        y: 100,
      ),
    );
    _log('hover sent=$hover');

    // Forced WS close: full rebuild through the reconnect controller.
    final statuses = <String>[];
    void onStatus() => statuses.add('${session.status.value}');
    session.status.addListener(onStatus);
    final streamBefore = session.videoStream.value;
    signalling.killSocket();
    _log('socket killed');
    await _until(
      () => session.status.value is StreamReconnecting,
      'reconnecting',
    );
    _log('status ${session.status.value}');
    await hostShot('04-reconnecting');
    await _until(() => _connected, 'reconnected');
    await _until(
      () =>
          session.videoStream.value != null &&
          !identical(session.videoStream.value, streamBefore),
      'new video stream',
    );
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

    // Mid-session credential refresh: setConfiguration + ICE restart.
    final offersBefore = signalling.sentTypes.where((t) => t == 'offer').length;
    final injected = signalling.injectRefresh();
    _log('refresh injected=$injected');
    await _sleep(8000);
    final offersAfter = signalling.sentTypes.where((t) => t == 'offer').length;
    _log(
      'refresh offers $offersBefore -> $offersAfter status=${session.status.value}',
    );
    await _deviceShot('08-after-refresh');
    await hostShot('07-after-refresh');

    await session.close();
    _log('DONE');
  }
}
