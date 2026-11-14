// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
// The fixture asserts wire bytes using the package's internal encoders.
// ignore_for_file: implementation_imports
import 'package:mobilerun_flutter/src/protocol/control_messages.dart';
import 'package:mobilerun_flutter/src/core/input/input_geometry.dart';

import 'debug_signalling.dart';

const _settingsTarget = Offset(73 / 488, 966 / 1080);

/// Runs input through the mounted view and asserts the resulting wire bytes.
final class InputE2eScript {
  InputE2eScript({
    required this.session,
    required this.debug,
    required this.controller,
    required this.viewKey,
    required this.outDir,
    required this.hostShot,
    required this.rotateView,
  });

  final DeviceStreamSession session;
  final DebugTransports debug;
  final DeviceStreamController controller;
  final GlobalKey viewKey;
  final Directory outDir;
  final Future<void> Function(String) hostShot;
  final Future<void> Function(bool) rotateView;

  List<Uint8List> get sent => debug.peers.last!.control.sent;
  void log(String text) => debugPrint('E2E $text');
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  List<Uint8List> press(int code) => [
    encodeKeycode(action: 0, keycode: code),
    encodeKeycode(action: 1, keycode: code),
  ];

  void expectFrames(int begin, List<Uint8List> expected, String what) {
    final actual = sent.skip(begin).toList();
    check(
      actual.length == expected.length &&
          actual.indexed.every(
            (entry) => listEquals(entry.$2, expected[entry.$1]),
          ),
      '$what: exact bytes',
    );
  }

  void system(DeviceSystemKey key) {
    final begin = sent.length;
    controller.sendSystemKey(key);
    expectFrames(
      begin,
      press(switch (key) {
        DeviceSystemKey.back => 4,
        DeviceSystemKey.home => 3,
        DeviceSystemKey.recent => 187,
      }),
      'system ${key.name}',
    );
  }

  Future<void> until(
    bool Function() condition,
    String what, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      final status = debug.signalling.rejectedStatus;
      if (status == 401 || status == 404) {
        throw StateError('device unavailable: HTTP $status');
      }
      if (DateTime.now().isAfter(deadline)) {
        log(
          'diagnostic status=${session.status.value} sent=${debug.sent.join(",")} received=${debug.received.join(",")}',
        );
        throw StateError('timeout: $what');
      }
      await wait(100);
    }
  }

  Offset point(double x, double y) {
    final box = viewKey.currentContext!.findRenderObject()! as RenderBox;
    final size = session.videoSize.value!;
    final rect = InputGeometry(box.size, size.width, size.height).rect;
    return box.localToGlobal(
      Offset(rect.left + x * rect.width, rect.top + y * rect.height),
    );
  }

  void pointer(PointerEvent event) =>
      GestureBinding.instance.handlePointerEvent(event);
  Future<void> tap(double x, double y, {int id = 41}) async {
    final p = point(x, y);
    final begin = sent.length;
    pointer(PointerDownEvent(pointer: id, position: p, buttons: 1));
    await wait(80);
    pointer(PointerUpEvent(pointer: id, position: p));
    final size = session.videoSize.value!;
    expectFrames(begin, [
      for (final action in [0, 1])
        encodeTouch(
          action: action,
          pointerId: 0,
          videoWidth: size.width,
          videoHeight: size.height,
          x: x * size.width,
          y: y * size.height,
          pressure: 1,
          actionButton: 1,
          buttons: 1,
        ),
    ], 'tap DOWN/UP slot 0');
    await wait(1500);
  }

  Future<void> tapSettings() => tap(_settingsTarget.dx, _settingsTarget.dy);

  Future<void> swipe({bool towardTop = false}) async {
    final start = point(.5, towardTop ? .25 : .78);
    final end = point(.5, towardTop ? .78 : .25);
    final begin = sent.length;
    pointer(PointerDownEvent(pointer: 42, position: start, buttons: 1));
    for (var i = 1; i <= 20; i++) {
      pointer(
        PointerMoveEvent(
          pointer: 42,
          position: Offset.lerp(start, end, i / 20)!,
          buttons: 1,
        ),
      );
      await wait(20);
    }
    pointer(PointerUpEvent(pointer: 42, position: end));
    final touches = sent.skip(begin).where((b) => b[0] == 2).toList();
    check(
      touches.length > 2 &&
          touches.first[1] == 0 &&
          touches.last[1] == 1 &&
          touches.skip(1).take(touches.length - 2).every((b) => b[1] == 2) &&
          touches.every((b) => ByteData.sublistView(b).getInt64(2) == 0),
      'swipe slot 0',
    );
    await wait(1800);
  }

  Future<void> shot(String name) async {
    await wait(800);
    final bytes = await session.screenshot();
    await outDir.create(recursive: true);
    await File('${outDir.path}/$name.png').writeAsBytes(bytes);
    await hostShot(name);
  }

  Future<void> checkRefresh() async {
    final offersBefore = debug.offerUfrags.length;
    final answersBefore = debug.received
        .where((type) => type == 'answer')
        .length;
    final framesBefore = await debug.framesDecoded() ?? 0;
    check(debug.injectRefresh(), 'no RTC configuration to replay');
    await until(
      () => debug.offerUfrags.length > offersBefore,
      'ICE restart offer',
    );
    check(
      debug.offerUfrags[offersBefore] != debug.offerUfrags[offersBefore - 1],
      'ICE restart must change the local ufrag',
    );
    await until(
      () =>
          debug.received.where((type) => type == 'answer').length >
          answersBefore,
      'ICE restart answer',
    );
    for (var i = 0; i < 32; i++) {
      await wait(500);
      check(
        session.status.value is StreamConnected,
        'disconnected during refresh',
      );
    }
    final framesAfter = await debug.framesDecoded() ?? 0;
    check(
      framesAfter - framesBefore >= 160,
      'frames did not continue after refresh',
    );
    log(
      'refresh: new ufrag, answer, frames $framesBefore -> $framesAfter over 16 s',
    );
  }

  Future<void> run() async {
    log('START input');
    session.status.addListener(() => log('status ${session.status.value}'));
    session.start();
    await until(
      () =>
          session.status.value is StreamConnected &&
          session.videoSize.value != null,
      'connected video',
    );
    await wait(3000);
    await shot('01-first-frame');
    // Bring Settings to the foreground before resetting its retained search
    // activity. BACK while the launcher is foreground cannot reset that task.
    system(DeviceSystemKey.home);
    await wait(1800);
    await tapSettings();
    for (var i = 0; i < 3; i++) {
      system(DeviceSystemKey.back);
      await wait(1000);
    }
    system(DeviceSystemKey.home);
    await wait(1800);
    await shot('02-before-tap');
    await tapSettings();
    await shot('03-after-tap');
    log('tap through widget');
    // Reset the list only after the isolated tap screenshot assertion.
    for (var i = 0; i < 3; i++) {
      await swipe(towardTop: true);
    }
    await shot('04-before-swipe');
    await swipe();
    await shot('05-after-swipe');
    log('swipe through widget');

    // Two independent fingers. The device may only act on one; bytes must
    // contain independent DOWN/MOVE/UP for both slots, never POINTER_DOWN.
    final begin = sent.length;
    pointer(
      PointerDownEvent(pointer: 50, position: point(.35, .5), buttons: 1),
    );
    pointer(
      PointerDownEvent(pointer: 51, position: point(.65, .5), buttons: 1),
    );
    for (var i = 1; i <= 8; i++) {
      pointer(
        PointerMoveEvent(
          pointer: 50,
          position: point(.35 - i * .02, .5),
          buttons: 1,
        ),
      );
      pointer(
        PointerMoveEvent(
          pointer: 51,
          position: point(.65 + i * .02, .5),
          buttons: 1,
        ),
      );
      await wait(30);
    }
    pointer(PointerUpEvent(pointer: 50, position: point(.19, .5)));
    pointer(PointerUpEvent(pointer: 51, position: point(.81, .5)));
    final touches = sent.skip(begin).where((b) => b[0] == 2).toList();
    final slots = touches
        .map((b) => ByteData.sublistView(b).getInt64(2))
        .toSet();
    check(
      slots.length == 2 &&
          slots.contains(0) &&
          slots.contains(1) &&
          touches.where((b) => b[1] == 0).length == 2 &&
          touches.where((b) => b[1] == 1).length == 2 &&
          touches.every((b) => b[1] <= 3),
      'multi-touch bytes',
    );
    log('pinch two slots=${slots.join(",")} messages=${touches.length}');
    await shot('06-after-pinch');

    // Rotate the local surface, preserve the cloud orientation, and tap the
    // same known target through a fresh letterboxed geometry.
    system(DeviceSystemKey.home);
    await wait(1800);
    await rotateView(true);
    await wait(800);
    check(session.videoSize.value != null, 'rotated geometry');
    await shot('07-rotated-home');
    await tapSettings();
    await shot('08-rotated-tap');
    await rotateView(false);
    await wait(700);
    system(DeviceSystemKey.back);
    system(DeviceSystemKey.recent);
    await shot('09-recent');
    system(DeviceSystemKey.home);
    await wait(1500);
    await tapSettings();
    // Settings search field (tap search icon, then the editor).
    await tap(.9, .065);
    await tap(.45, .065);
    controller.showKeyboard();
    await wait(1500);
    // Exercise the TextInputClient path with a committed value. The host
    // also taps the visible platform keyboard during this checkpoint.
    for (final character in 'display'.split('')) {
      final begin = sent.length;
      TextInput.updateEditingValue(TextEditingValue(text: '\u200b$character'));
      expectFrames(begin, [encodeText(character)], 'immediate IME character');
    }
    await shot('10-soft-keyboard');
    final beforeHost = sent.length;
    log('HOST-TYPE');
    await wait(7000);
    final platformText = sent.skip(beforeHost).toList();
    check(
      platformText.length == 3 &&
          platformText.every(
            (bytes) =>
                bytes[0] == 1 &&
                utf8.decode(bytes.sublist(5)).runes.length == 1,
          ),
      'platform keyboard must commit exactly three one-character text frames',
    );
    log('platform keyboard committed 3 one-character frames');
    final beforeDelete = sent.length;
    TextInput.updateEditingValue(TextEditingValue.empty);
    expectFrames(beforeDelete, press(67), 'IME empty-buffer DEL');
    controller.hideKeyboard();
    await wait(700);
    await shot('11-platform-text');
    log('IME text, empty-buffer DEL and keyboard hide routed');

    final hoverStart = debug.peers.last!.hover.sent.length;
    final scrollStart = sent.length;
    final size = session.videoSize.value!;
    pointer(
      PointerHoverEvent(
        position: point(.5, .3),
        kind: PointerDeviceKind.mouse,
        buttons: 2,
      ),
    );
    pointer(
      PointerScrollEvent(
        position: point(.5, .5),
        scrollDelta: const Offset(0, 100),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await wait(500);
    final hover = debug.peers.last!.hover.sent.skip(hoverStart).toList();
    check(
      hover.length == 1 &&
          listEquals(
            hover.single,
            encodeHover(
              videoWidth: size.width,
              videoHeight: size.height,
              x: size.width * .5,
              y: size.height * .3,
              buttons: 2,
            ),
          ),
      'hover exact bytes on hover channel',
    );
    expectFrames(scrollStart, [
      encodeScroll(
        videoWidth: size.width,
        videoHeight: size.height,
        x: size.width * .5,
        y: size.height * .5,
        hscrollTicks: 0,
        vscrollTicks: -1,
      ),
    ], 'scroll exact bytes on control channel');
    log('hover/scroll exact bytes on separate channels');
    system(DeviceSystemKey.home);
    await shot('12-final-home');

    // Preserve the connection slice's forced-close/rebuild and control proof.
    final oldPeer = debug.peers.last;
    debug.killSocket();
    await until(
      () => session.status.value is StreamReconnecting,
      'reconnecting',
    );
    log('socket killed; reconnecting');
    await hostShot('13-reconnecting');
    await until(
      () =>
          session.status.value is StreamConnected &&
          debug.peers.last != oldPeer &&
          session.videoSize.value != null,
      'rebuilt video',
    );
    await wait(2500);
    await shot('14-after-reconnect');
    system(DeviceSystemKey.home);
    await wait(1800);
    await shot('15-reconnected-before-tap');
    await tapSettings();
    await shot('16-reconnected-after-tap');
    log('reconnected tap exact bytes');
    await checkRefresh();
    await shot('17-after-refresh');
    await session.close();
  }
}
