// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal input implementation; not exported by the package.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:flutter/widgets.dart' show StringCharacters;

import '../../protocol/constants.dart';
import '../../protocol/control_messages.dart';

enum KeyRoute { ignored, handled, paste }

final _modifierKey = RegExp(r'^(Shift|Control|Alt|Meta)');
final _letterCode = RegExp(r'^Key[A-Z]$');

bool isPrintableRune(int rune) => rune >= 0x20 && (rune < 0x7f || rune > 0x9f);

bool _isControlKey(String? key) =>
    const {
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
    }.contains(key) ||
    key?.startsWith('Arrow') == true ||
    (key?.startsWith('F') == true && key!.length <= 3) ||
    _modifierKey.hasMatch(key ?? '');

void pressKey(int keycode, void Function(Uint8List) send) {
  send(encodeKeycode(action: AndroidKeys.actionDown, keycode: keycode));
  send(encodeKeycode(action: AndroidKeys.actionUp, keycode: keycode));
}

/// Stateful keyboard routing, balancing only keycode DOWNs sent by this input.
final class KeyInput {
  final _pressed = <String>{};

  void clear() => _pressed.clear();

  /// React's shortcut → control → single-character text → fallback order.
  /// Releases only keycodes tracked on DOWN; text keys have no release frame.
  KeyRoute route({
    required String? code,
    required String? text,
    required bool down,
    required void Function(Uint8List) send,
    bool shift = false,
    bool control = false,
    bool alt = false,
    bool meta = false,
    bool capsLock = false,
  }) {
    final shortcut = control || meta;
    final keycode = keyboardCodeMap[code];
    if (!down && !_pressed.remove(code)) return KeyRoute.ignored;
    if (down && shortcut) {
      final letter = text?.toLowerCase();
      if (letter == 'v') return KeyRoute.paste;
      if (letter == 'm') {
        pressKey(AndroidKeys.menu, send);
        return KeyRoute.handled;
      }
    }
    if (down &&
        !shortcut &&
        !_isControlKey(text) &&
        text != null &&
        (text.length == 1 ||
            (text.isNotEmpty &&
                text.runes.every(isPrintableRune) &&
                text.characters.length == 1))) {
      send(encodeText(text));
      return KeyRoute.handled;
    }
    if (keycode == null) return KeyRoute.ignored;
    final letter = _letterCode.hasMatch(code!);
    final effectiveShift = letter ? shift != capsLock : shift;
    final metaState =
        (effectiveShift ? AndroidKeys.metaShiftOn : 0) |
        (control ? AndroidKeys.metaCtrlOn : 0) |
        (alt ? AndroidKeys.metaAltOn : 0) |
        (meta ? AndroidKeys.metaMetaOn : 0);
    if (down) _pressed.add(code);
    send(
      encodeKeycode(
        action: down ? AndroidKeys.actionDown : AndroidKeys.actionUp,
        keycode: keycode,
        metaState: metaState,
      ),
    );
    return KeyRoute.handled;
  }
}
