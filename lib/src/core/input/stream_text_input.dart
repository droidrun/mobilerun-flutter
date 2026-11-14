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
          inputType: TextInputType.multiline,
          inputAction: TextInputAction.newline,
          autocorrect: false,
          enableSuggestions: false,
          enableDeltaModel: true,
        ),
      );
      _connection!.setEditingState(_value);
    }
    if (show) _connection!.show();
  }

  void close() {
    _connection?.close();
    _connection = null;
    _value = _empty;
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
      final lines = text
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) pressKey(AndroidKeys.enter, send);
        if (lines[i].isNotEmpty) send(encodeText(lines[i]));
      }
    } else if (previous == _empty && value.text.isEmpty) {
      pressKey(AndroidKeys.del, send);
    }
    // Keep marked text local, reset only once it has been committed/cancelled.
    _value = _empty;
    _connection?.setEditingState(_value);
  }

  @override
  void performAction(TextInputAction action) {
    if (active() && action != TextInputAction.none) {
      pressKey(AndroidKeys.enter, send);
    }
  }

  @override
  void connectionClosed() {
    _connection = null;
    _value = _empty;
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
}
