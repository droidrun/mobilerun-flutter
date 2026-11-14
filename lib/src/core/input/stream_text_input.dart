// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal input implementation; not exported by the package.
// ignore_for_file: public_member_api_docs

import 'package:flutter/services.dart';

import '../../protocol/constants.dart';
import '../../protocol/control_messages.dart';
import 'key_input.dart';

/// A local composition buffer. The sentinel gives mobile IMEs one character
/// to delete even when the remote editor's contents are unknown to Flutter.
final class StreamTextInput with TextInputClient, DeltaTextInputClient {
  StreamTextInput({required this.active, required this.send});

  final bool Function() active;
  final void Function(Uint8List) send;
  static const _sentinel = '\u200b';
  static const _empty = TextEditingValue(
    text: _sentinel,
    selection: TextSelection.collapsed(offset: 1),
  );
  TextEditingValue _value = _empty;
  TextInputConnection? _connection;

  void attach({bool show = false}) {
    if (!active()) return;
    if (_connection?.attached != true) {
      _value = _empty;
      _connection = TextInput.attach(
        this,
        const TextInputConfiguration(
          // Android's visible-password variation commits ordinary characters
          // immediately instead of buffering the current word for suggestions.
          inputType: TextInputType.visiblePassword,
          inputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          enableDeltaModel: true,
        ),
      );
      _connection!.setEditingState(_value);
    }
    if (show) _connection!.show();
  }

  void close() {
    // TextInputConnection.attached identifies the current platform client.
    // A stale connection must never clear or hide a host editor's keyboard.
    if (_connection?.attached == true) _connection!.close();
    _connection = null;
    _value = _empty;
  }

  void hide() {
    if (_connection?.attached == true) {
      _finishComposition();
      close();
    }
  }

  void _finishComposition() {
    if (active() && _value.text != _sentinel && _value.text.isNotEmpty) {
      updateEditingValue(_value.copyWith(composing: TextRange.empty));
    }
  }

  @override
  TextEditingValue get currentTextEditingValue => _value;
  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    if (!active()) return;
    var value = _value;
    for (final delta in deltas) {
      value = delta.apply(value);
    }
    // One platform batch may include insertion and selection/composition
    // changes for the same text. Commit that batch once before resetting.
    if (deltas.isNotEmpty) updateEditingValue(value);
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    if (!active()) return;
    final previous = _value;
    _value = value;
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    final text = value.text.startsWith(_sentinel)
        ? value.text.substring(1)
        : value.text;
    if (text.isNotEmpty) {
      _commitText(text);
    } else if (previous == _empty && value.text.isEmpty) {
      pressKey(AndroidKeys.del, send);
    }
    // Keep marked text local, reset only once it has been committed/cancelled.
    _value = _empty;
    _connection?.setEditingState(_value);
  }

  void _commitText(String text) {
    final printable = StringBuffer();
    void flush() {
      if (printable.isEmpty) return;
      send(encodeText(printable.toString()));
      printable.clear();
    }

    for (final rune
        in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').runes) {
      final key = switch (rune) {
        0x0a => AndroidKeys.enter,
        0x09 => AndroidKeys.keycodeTab,
        0x08 => AndroidKeys.del,
        _ => null,
      };
      if (key != null) {
        flush();
        pressKey(key, send);
      } else if (rune >= 0x20 && (rune < 0x7f || rune > 0x9f)) {
        printable.writeCharCode(rune);
      }
    }
    flush();
  }

  @override
  void performAction(TextInputAction action) {
    if (active() && action != TextInputAction.none) {
      _finishComposition();
      pressKey(AndroidKeys.enter, send);
    }
  }

  @override
  void connectionClosed() {
    _connection = null;
    _finishComposition();
    _value = _empty;
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
}
