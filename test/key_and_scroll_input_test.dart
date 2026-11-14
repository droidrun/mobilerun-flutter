// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/input/key_input.dart';
import 'package:mobilerun_flutter/src/core/input/physical_key_codes.dart';
import 'package:mobilerun_flutter/src/core/input/scroll_input.dart';

void main() {
  for (final code in keyboardCodeMap.keys) {
    test('USB HID mapping covers fixture $code', () {
      final entry = physicalKeyCodes.entries.singleWhere(
        (e) => e.value == code,
      );
      expect(PhysicalKeyboardKey.findKeyByCode(entry.key), isNotNull);
    });
  }
  test('printable characters send text without key-up', () {
    final sent = <Uint8List>[];
    for (final down in [true, false]) {
      routeKey(code: 'KeyA', text: 'é', down: down, send: sent.add);
    }
    expect(sent.length, 1);
    expect(utf8.decode(sent.single.sublist(5)), 'é');
  });
  test('paste precedes control injection, menu sends a complete press', () {
    final sent = <Uint8List>[];
    expect(
      routeKey(
        code: 'KeyV',
        text: null,
        down: true,
        control: true,
        send: sent.add,
      ),
      KeyRoute.paste,
    );
    expect(sent, isEmpty);
    expect(
      routeKey(
        code: 'KeyV',
        text: '\u0016',
        down: true,
        control: true,
        send: sent.add,
      ),
      KeyRoute.paste,
    );
    expect(sent, isEmpty);
    routeKey(code: 'KeyM', text: 'm', down: true, meta: true, send: sent.add);
    expect(sent, [
      encodeKeycode(action: 0, keycode: 82),
      encodeKeycode(action: 1, keycode: 82),
    ]);
  });
  for (final code in [
    'Backspace',
    'Delete',
    'Enter',
    'Tab',
    'Escape',
    'Home',
    'End',
    'PageUp',
    'PageDown',
    'Insert',
    'ArrowLeft',
    'F12',
    'ShiftLeft',
    'ControlRight',
    'AltLeft',
    'MetaRight',
  ]) {
    test('$code sends down and up keycodes', () {
      final sent = <Uint8List>[];
      for (final down in [true, false]) {
        routeKey(code: code, text: null, down: down, send: sent.add);
      }
      expect(sent, [
        encodeKeycode(action: 0, keycode: keyboardCodeMap[code]!),
        encodeKeycode(action: 1, keycode: keyboardCodeMap[code]!),
      ]);
    });
  }
  test('ctrl combo uses caps XOR shift plus ctrl/alt/meta flags', () {
    final sent = <Uint8List>[];
    routeKey(
      code: 'KeyA',
      text: 'a',
      down: true,
      control: true,
      shift: true,
      capsLock: true,
      alt: true,
      meta: true,
      send: sent.add,
    );
    expect(
      sent.single,
      encodeKeycode(action: 0, keycode: 29, metaState: 4096 | 2 | 65536),
    );
    routeKey(
      code: 'KeyA',
      text: 'a',
      down: true,
      control: true,
      capsLock: true,
      send: sent.add,
    );
    expect(
      sent.last,
      encodeKeycode(action: 0, keycode: 29, metaState: 4096 | 1),
    );
  });
  test('unknown keys ignored, mapped dead keys use keydown fallback', () {
    final sent = <Uint8List>[];
    expect(
      routeKey(code: null, text: null, down: true, send: sent.add),
      KeyRoute.ignored,
    );
    routeKey(code: 'Quote', text: null, down: true, send: sent.add);
    expect(sent.single, encodeKeycode(action: 0, keycode: 75));
  });
  for (final unit in ScrollUnit.values) {
    test(
      'scroll ${unit.name}: React tick conversion before S1 fixed point',
      () {
        final factor = [0.01, 1.0, 3.0][unit.index];
        expect(
          scrollTicks(const Offset(2, -4), unit: unit),
          Offset(-2 * factor, 4 * factor),
        );
      },
    );
  }
}
