// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal input implementation; not exported by the package.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import '../../protocol/constants.dart';
import '../../protocol/control_messages.dart';

enum KeyRoute { ignored, handled, paste }

final _functionCode = RegExp(r'^F\d{1,2}$');
final _modifierCode = RegExp(r'^(Shift|Control|Alt|Meta)');
final _letterCode = RegExp(r'^Key[A-Z]$');

bool isPrintableRune(int rune) => rune >= 0x20 && (rune < 0x7f || rune > 0x9f);

bool _isControlCode(String? code) =>
    const {
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
    }.contains(code) ||
    code?.startsWith('Arrow') == true ||
    _functionCode.hasMatch(code ?? '') ||
    _modifierCode.hasMatch(code ?? '');

String? _shortcutLetter(String? code, String? text) {
  if (text != null &&
      text.runes.length == 1 &&
      isPrintableRune(text.runes.single)) {
    return text.toLowerCase();
  }
  if (code == null || !_letterCode.hasMatch(code)) return null;
  return code.substring(3).toLowerCase();
}

void pressKey(int keycode, void Function(Uint8List) send) {
  send(encodeKeycode(action: AndroidKeys.actionDown, keycode: keycode));
  send(encodeKeycode(action: AndroidKeys.actionUp, keycode: keycode));
}

/// React's shortcut → control → single-character text → fallback order.
/// Pass the down event's character again on release: Flutter key-up events
/// omit it, but text keys must not produce a fallback keycode release.
KeyRoute routeKey({
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
  if (down && shortcut) {
    final letter = _shortcutLetter(code, text);
    if (letter == 'v') return KeyRoute.paste;
    if (letter == 'm') {
      pressKey(AndroidKeys.menu, send);
      return KeyRoute.handled;
    }
  }
  if (!shortcut &&
      (keycode == null || !_isControlCode(code)) &&
      text?.runes.length == 1) {
    if (down) send(encodeText(text!));
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
  send(
    encodeKeycode(
      action: down ? AndroidKeys.actionDown : AndroidKeys.actionUp,
      keycode: keycode,
      metaState: metaState,
    ),
  );
  return KeyRoute.handled;
}
