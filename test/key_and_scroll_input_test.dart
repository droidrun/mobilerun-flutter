// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/protocol/control_messages.dart';
import 'package:mobilerun_flutter/src/protocol/constants.dart';
import 'package:mobilerun_flutter/src/core/input/key_input.dart';
import 'package:mobilerun_flutter/src/core/input/physical_key_codes.dart';
import 'package:mobilerun_flutter/src/core/input/scroll_input.dart';

void main() {
  late KeyInput keys;
  setUp(() => keys = KeyInput());
  for (final code in keyboardCodeMap.keys) {
    test('USB HID mapping covers fixture $code', () {
      final entry = physicalKeyCodes.entries.singleWhere(
        (e) => e.value == code,
      );
      expect(
        PhysicalKeyboardKey.findKeyByCode(
          entry.key,
        )!.debugName!.replaceAll(' ', ''),
        code,
      );
      expect(logicalKeyCodes.values, contains(code));
    });
  }
  test('printable characters send text without key-up', () {
    final sent = <Uint8List>[];
    for (final down in [true, false]) {
      keys.route(code: 'KeyA', text: 'é', down: down, send: sent.add);
    }
    expect(sent, [encodeText('é')]);
  });
  test('paste precedes control injection, menu sends a complete press', () {
    final sent = <Uint8List>[];
    expect(
      keys.route(
        code: 'KeyV',
        text: 'v',
        down: true,
        control: true,
        send: sent.add,
      ),
      KeyRoute.paste,
    );
    expect(sent, isEmpty);
    expect(
      keys.route(
        code: 'KeyV',
        text: 'V',
        down: true,
        control: true,
        send: sent.add,
      ),
      KeyRoute.paste,
    );
    expect(sent, isEmpty);
    keys.route(code: 'KeyM', text: 'm', down: true, meta: true, send: sent.add);
    expect(sent, [
      encodeKeycode(action: 0, keycode: 82),
      encodeKeycode(action: 1, keycode: 82),
    ]);
  });
  for (final code in [
    'Backspace',
    'Delete',
    'Enter',
    'NumpadEnter',
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
        keys.route(
          code: code,
          text: code == 'NumpadEnter' ? 'Enter' : code,
          down: down,
          send: sent.add,
        );
      }
      expect(sent, [
        encodeKeycode(action: 0, keycode: keyboardCodeMap[code]!),
        encodeKeycode(action: 1, keycode: keyboardCodeMap[code]!),
      ]);
    });
  }
  test('ctrl combo uses caps XOR shift plus ctrl/alt/meta flags', () {
    final sent = <Uint8List>[];
    keys.route(
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
    keys.route(
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
  for (final code in [
    null,
    'AudioVolumeUp',
    'MediaPlayPause',
    'Camera',
    'GamepadA',
    'F13',
    'F123',
  ]) {
    test('unmapped $code without text is ignored', () {
      final sent = <Uint8List>[];
      for (final down in [true, false]) {
        expect(
          keys.route(
            code: code,
            text: code == 'NumpadEnter' ? 'Enter' : code,
            down: down,
            send: sent.add,
          ),
          KeyRoute.ignored,
        );
      }
      expect(sent, isEmpty);
    });
    test('unmapped $code with single-character text follows React', () {
      final sent = <Uint8List>[];
      for (final down in [true, false]) {
        expect(
          keys.route(code: code, text: 'x', down: down, send: sent.add),
          down ? KeyRoute.handled : KeyRoute.ignored,
        );
      }
      expect(sent, [encodeText('x')]);
    });
  }
  for (final text in [
    '\u0000',
    '\b',
    '\t',
    '\n',
    '\u001b',
    '\u007f',
    '\u0085',
  ]) {
    test(
      'hardware character ${text.codeUnitAt(0)} follows React text branch',
      () {
        final sent = <Uint8List>[];
        for (final down in [true, false]) {
          keys.route(code: 'KeyA', text: text, down: down, send: sent.add);
        }
        expect(sent, [encodeText(text)]);
      },
    );
  }
  for (final code in ['ContextMenu', 'Numpad1', 'Quote', 'KeyA']) {
    test('mapped $code without text releases its fallback keycode', () {
      final sent = <Uint8List>[];
      for (final down in [true, false]) {
        keys.route(
          code: code,
          text: null,
          down: down,
          alt: true,
          send: sent.add,
        );
      }
      expect(sent, [
        encodeKeycode(action: 0, keycode: keyboardCodeMap[code]!, metaState: 2),
        encodeKeycode(action: 1, keycode: keyboardCodeMap[code]!, metaState: 2),
      ]);
    });
  }
  test('Flutter pixel scroll converts to React ticks', () {
    expect(scrollTicks(const Offset(2, -4)), const Offset(-.02, .04));
  });
}
