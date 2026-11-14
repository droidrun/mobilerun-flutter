// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show Endian;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'debug_signalling.dart';

/// Runs input through the mounted widget and asserts the resulting wire
/// messages. Device and emulator screenshots provide visual evidence too.
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

  Future<void> until(bool Function() condition, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
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
    final rect = controller.renderedVideoRect!;
    final box = viewKey.currentContext!.findRenderObject()! as RenderBox;
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
    final touches = sent.skip(begin).where((b) => b[0] == 2).toList();
    check(
      touches.length == 2 &&
          touches[0][1] == 0 &&
          touches[1][1] == 1 &&
          ByteData.sublistView(touches[0]).getInt64(2) == 0 &&
          ByteData.sublistView(touches[1]).getInt64(2) == 0,
      'tap DOWN/UP slot 0',
    );
    await wait(1500);
  }

  Future<void> swipe() async {
    final start = point(.5, .78), end = point(.5, .25);
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

  Future<void> run() async {
    log('START input');
    session.status.addListener(() => log('status ${session.status.value}'));
    session.start();
    await until(
      () =>
          session.status.value is StreamConnected &&
          controller.renderedVideoRect != null,
      'connected video',
    );
    await wait(3000);
    await shot('01-first-frame');
    system(DeviceSystemKey.home);
    await wait(1800);
    await shot('02-before-tap');
    await tap(73 / 488, 966 / 1080);
    await shot('03-after-tap');
    log('tap through widget');
    await shot('08-before-swipe');
    await swipe();
    await shot('09-after-swipe');
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
    await shot('10-after-pinch');

    // Rotate the local surface, preserve the cloud orientation, and tap the
    // same known target through a fresh letterboxed geometry.
    system(DeviceSystemKey.home);
    await wait(1800);
    await rotateView(true);
    await wait(800);
    check(controller.renderedVideoRect != null, 'rotated geometry');
    await shot('11-rotated-home');
    await tap(73 / 488, 966 / 1080);
    await shot('11-rotated-tap');
    await rotateView(false);
    await wait(700);
    system(DeviceSystemKey.back);
    system(DeviceSystemKey.recent);
    await shot('12-recent');
    system(DeviceSystemKey.home);
    await wait(1500);
    await tap(73 / 488, 966 / 1080);
    // Settings search field (tap search icon, then the editor).
    await tap(.9, .065);
    await tap(.45, .065);
    controller.showKeyboard();
    await wait(1500);
    final beforeText = sent.length;
    // Exercise the TextInputClient path with a committed value. The host
    // also taps the visible platform keyboard during this checkpoint.
    for (final character in 'display'.split('')) {
      final begin = sent.length;
      TextInput.updateEditingValue(TextEditingValue(text: '\u200b$character'));
      expectFrames(begin, [encodeText(character)], 'immediate IME character');
    }
    await shot('13-soft-keyboard');
    final beforeHost = sent.length;
    log('HOST-TYPE');
    await wait(7000);
    check(sent.skip(beforeText).any((b) => b[0] == 1), 'IME text was not sent');
    check(
      sent.skip(beforeHost).any((b) => b[0] == 1),
      'platform keyboard did not commit text',
    );
    final beforeDelete = sent.length;
    TextInput.updateEditingValue(TextEditingValue.empty);
    expectFrames(beforeDelete, press(67), 'IME empty-buffer DEL');
    controller.hideKeyboard();
    await wait(700);
    final beforeHardware = sent.length;
    // The host injects real emulator keyboard events. Calling HardwareKeyboard
    // directly skips Flutter's Focus dispatch and cannot prove this path.
    log('HOST-HARDWARE');
    await until(() => sent.length >= beforeHardware + 5, 'host hardware keys');
    expectFrames(beforeHardware, [
      encodeText('a'),
      ...press(67),
      ...press(66),
    ], 'hardware text/DEL/ENTER');
    await shot('14-hardware-text');
    check(
      sent.any(
        (b) =>
            b[0] == 0 &&
            ByteData.sublistView(b).getInt32(2, Endian.little) == 67,
      ),
      'Backspace key missing',
    );
    log('IME/hardware text, Backspace and Enter routed');

    final hoverStart = debug.peers.last!.hover.sent.length;
    pointer(
      PointerHoverEvent(position: point(.5, .3), kind: PointerDeviceKind.mouse),
    );
    pointer(
      PointerScrollEvent(
        position: point(.5, .5),
        scrollDelta: const Offset(0, 100),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await wait(500);
    check(
      debug.peers.last!.hover.sent.length > hoverStart &&
          sent.every((b) => b[0] != 21) &&
          sent.any((b) => b[0] == 3),
      'hover/scroll routing',
    );
    log('hover channel only; pixel scroll sent');
    system(DeviceSystemKey.home);
    await shot('15-final-home');
    await session.close();
  }
}
