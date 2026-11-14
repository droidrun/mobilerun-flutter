// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal input implementation; not exported by the package.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import '../../protocol/constants.dart';
import '../../protocol/control_messages.dart';

enum KeyRoute { ignored, sent, paste }

void pressKey(int keycode, void Function(Uint8List) send) {
  send(encodeKeycode(action: AndroidKeys.actionDown, keycode: keycode));
  send(encodeKeycode(action: AndroidKeys.actionUp, keycode: keycode));
}

/// React's shortcut → control → printable → fallback order.
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
  // Physical key identity still works when a platform omits the character on
  // shortcut events (notably macOS).
  final shortcutText =
      text != null && text.runes.length == 1 && text.runes.single >= 0x20
      ? text.toLowerCase()
      : null;
  final shortcutLetter =
      shortcutText ??
      (code?.startsWith('Key') == true
          ? code!.substring(3).toLowerCase()
          : null);
  if (down && shortcut && shortcutLetter == 'v') return KeyRoute.paste;
  if (down && shortcut && shortcutLetter == 'm') {
    pressKey(AndroidKeys.menu, send);
    return KeyRoute.sent;
  }
  final keycode = keyboardCodeMap[code];
  final isControl =
      shortcut ||
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
      }.contains(code) ||
      code?.startsWith('Arrow') == true ||
      RegExp(r'^F\d{1,2}$').hasMatch(code ?? '') ||
      RegExp(r'^(Shift|Control|Alt|Meta)').hasMatch(code ?? '');
  if (!isControl && down && text != null && text.runes.length == 1) {
    send(encodeText(text));
    return KeyRoute.sent;
  }
  if (keycode == null) return KeyRoute.ignored;
  if (isControl || down) {
    final letter = RegExp(r'^Key[A-Z]$').hasMatch(code ?? '');
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
  }
  return KeyRoute.sent;
}
