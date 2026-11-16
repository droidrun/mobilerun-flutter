// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/protocol/control_messages.dart';
import 'package:mobilerun_flutter/src/core/input/stream_text_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a platform delta batch commits once after its selection update', () {
    final sent = <Uint8List>[];
    final input = StreamTextInput(active: () => true, send: sent.add);
    input.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: '\u200b',
        textInserted: 'a',
        insertionOffset: 1,
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
      const TextEditingDeltaInsertion(
        oldText: '\u200ba',
        textInserted: 'b',
        insertionOffset: 2,
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange.empty,
      ),
      const TextEditingDeltaNonTextUpdate(
        oldText: '\u200bab',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange.empty,
      ),
    ]);
    expect(sent, [encodeText('ab')]);
  });
  test('stale non-text delta after reset cannot duplicate committed text', () {
    final sent = <Uint8List>[];
    final input = StreamTextInput(active: () => true, send: sent.add);
    input.updateEditingValueWithDeltas([
      const TextEditingDeltaInsertion(
        oldText: '\u200b',
        textInserted: 'a',
        insertionOffset: 1,
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
    ]);
    input.updateEditingValueWithDeltas([
      const TextEditingDeltaNonTextUpdate(
        oldText: '\u200ba',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
    ]);
    expect(sent, [encodeText('a')]);
    expect(input.currentTextEditingValue.text, '\u200b');
  });
  test('stale empty update after delete cannot duplicate DEL', () {
    final sent = <Uint8List>[];
    final input = StreamTextInput(active: () => true, send: sent.add);
    input.updateEditingValueWithDeltas([
      const TextEditingDeltaDeletion(
        oldText: '\u200b',
        deletedRange: TextRange(start: 0, end: 1),
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange.empty,
      ),
    ]);
    input.updateEditingValueWithDeltas([
      const TextEditingDeltaNonTextUpdate(
        oldText: '',
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange.empty,
      ),
    ]);
    expect(sent, [
      encodeKeycode(action: 0, keycode: 67),
      encodeKeycode(action: 1, keycode: 67),
    ]);
  });
  test('marked text stays local, committed composition sent once', () {
    final sent = <Uint8List>[];
    final input = StreamTextInput(active: () => true, send: sent.add);
    input.updateEditingValue(
      const TextEditingValue(
        text: '\u200bに',
        composing: TextRange(start: 1, end: 2),
      ),
    );
    input.updateEditingValue(
      const TextEditingValue(
        text: '\u200b日本',
        composing: TextRange(start: 1, end: 3),
      ),
    );
    expect(sent, isEmpty);
    input.updateEditingValue(const TextEditingValue(text: '\u200b日本'));
    expect(sent, [encodeText('日本')]);
    expect(input.currentTextEditingValue.text, '\u200b');
  });
  test(
    'deleting sentinel on empty buffer emits DEL pair, action ENTER pair',
    () {
      final sent = <Uint8List>[];
      final input = StreamTextInput(active: () => true, send: sent.add);
      input.updateEditingValueWithDeltas([
        const TextEditingDeltaDeletion(
          oldText: '\u200b',
          deletedRange: TextRange(start: 0, end: 1),
          selection: TextSelection.collapsed(offset: 0),
          composing: TextRange.empty,
        ),
      ]);
      input.performAction(TextInputAction.done);
      expect(sent, [
        encodeKeycode(action: 0, keycode: 67),
        encodeKeycode(action: 1, keycode: 67),
        encodeKeycode(action: 0, keycode: 66),
        encodeKeycode(action: 1, keycode: 66),
      ]);
    },
  );
  test('multiline commit uses text and ENTER, cancellation emits nothing', () {
    final sent = <Uint8List>[];
    final input = StreamTextInput(active: () => true, send: sent.add);
    input.updateEditingValue(
      const TextEditingValue(
        text: '\u200bx',
        composing: TextRange(start: 1, end: 2),
      ),
    );
    input.updateEditingValue(const TextEditingValue(text: '\u200b'));
    expect(sent, isEmpty);
    input.updateEditingValue(const TextEditingValue(text: '\u200bone\r\ntwo'));
    expect(sent, [
      encodeText('one'),
      encodeKeycode(action: 0, keycode: 66),
      encodeKeycode(action: 1, keycode: 66),
      encodeText('two'),
    ]);
  });
  test('ordinary characters commit immediately and implicit composition finalization commits once', () {
    final sent = <Uint8List>[];
    final input = StreamTextInput(active: () => true, send: sent.add);
    input.updateEditingValue(const TextEditingValue(text: '\u200ba'));
    expect(sent, [encodeText('a')]);
    input.updateEditingValue(const TextEditingValue(text: '\u200bb'));
    expect(sent, [encodeText('a'), encodeText('b')]);
    input.updateEditingValue(
      const TextEditingValue(
        text: '\u200b日本',
        composing: TextRange(start: 1, end: 3),
      ),
    );
    input.connectionClosed();
    input.connectionClosed();
    expect(sent, [encodeText('a'), encodeText('b'), encodeText('日本')]);
    expect(input.currentTextEditingValue.text, '\u200b');
  });
  test('editor action finalizes marked text before ENTER', () {
    final sent = <Uint8List>[];
    final input = StreamTextInput(active: () => true, send: sent.add);
    input.updateEditingValue(
      const TextEditingValue(
        text: '\u200bé',
        composing: TextRange(start: 1, end: 2),
      ),
    );
    input.performAction(TextInputAction.done);
    expect(sent, [
      encodeText('é'),
      encodeKeycode(action: 0, keycode: 66),
      encodeKeycode(action: 1, keycode: 66),
    ]);
  });
  test('IME control characters use key pairs or are discarded, never text', () {
    final sent = <Uint8List>[];
    final input = StreamTextInput(active: () => true, send: sent.add);
    input.updateEditingValue(
      const TextEditingValue(text: '\u200ba\r\tb\u0000\u007f\b\n'),
    );
    expect(sent, [
      encodeText('a'),
      encodeKeycode(action: 0, keycode: 66),
      encodeKeycode(action: 1, keycode: 66),
      encodeKeycode(action: 0, keycode: 61),
      encodeKeycode(action: 1, keycode: 61),
      encodeText('b'),
      encodeKeycode(action: 0, keycode: 66),
      encodeKeycode(action: 1, keycode: 66),
    ]);
  });
  test('no input after control or focus is lost', () {
    final sent = <Uint8List>[];
    final input = StreamTextInput(active: () => false, send: sent.add);
    input.updateEditingValue(const TextEditingValue(text: 'text'));
    input.performAction(TextInputAction.done);
    expect(sent, isEmpty);
  });
}
