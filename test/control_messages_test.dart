// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/protocol/control_messages.dart';

import 'support/fixtures.dart';

typedef _Encoder = Uint8List Function(Map<String, Object?> args);

int _int(Map<String, Object?> args, String key) => args[key]! as int;
num _num(Map<String, Object?> args, String key) => args[key]! as num;

final Map<String, _Encoder> _encoders = {
  'touch': (a) => encodeTouch(
    action: _int(a, 'action'),
    pointerId: _int(a, 'pointerId'),
    videoWidth: _int(a, 'videoWidth'),
    videoHeight: _int(a, 'videoHeight'),
    x: _num(a, 'x'),
    y: _num(a, 'y'),
    pressure: _num(a, 'pressure'),
    actionButton: _int(a, 'actionButton'),
    buttons: _int(a, 'buttons'),
  ),
  'scroll': (a) => encodeScroll(
    videoWidth: _int(a, 'videoWidth'),
    videoHeight: _int(a, 'videoHeight'),
    x: _num(a, 'x'),
    y: _num(a, 'y'),
    hscrollTicks: _num(a, 'hscrollTicks'),
    vscrollTicks: _num(a, 'vscrollTicks'),
    buttons: _int(a, 'buttons'),
  ),
  'hover': (a) => encodeHover(
    videoWidth: _int(a, 'videoWidth'),
    videoHeight: _int(a, 'videoHeight'),
    x: _num(a, 'x'),
    y: _num(a, 'y'),
    buttons: _int(a, 'buttons'),
  ),
  'keycode': (a) => encodeKeycode(
    action: _int(a, 'action'),
    keycode: _int(a, 'keycode'),
    repeat: _int(a, 'repeat'),
    metaState: _int(a, 'metaState'),
  ),
  'text': (a) => encodeText(a['text']! as String),
  'set-clipboard': (a) => encodeSetClipboard(
    text: a['text']! as String,
    paste: a['paste']! as bool,
  ),
};

void main() {
  for (final entry in _encoders.entries) {
    final cases = readObjects('control/${entry.key}.json', 'cases');
    group('control/${entry.key}', () {
      test('has fixture cases', () => expect(cases, isNotEmpty));
      for (final fixtureCase in cases) {
        test(fixtureCase['name']! as String, () {
          final args = asObject(fixtureCase['args']);
          expect(toHex(entry.value(args)), fixtureCase['hex']);
        });
      }
    });
  }

  group('unpaired UTF-16 surrogates encode as U+FFFD', () {
    const replacement = 'efbfbd';
    const cases = {
      'lone high surrogate': ('\uD83D', replacement),
      'lone low surrogate between ascii': ('a\uDC00b', '61${replacement}62'),
      'trailing high surrogate': ('ok\uD83D', '6f6b$replacement'),
    };
    for (final entry in cases.entries) {
      final (text, bytesHex) = entry.value;
      final lengthHex = (bytesHex.length ~/ 2)
          .toRadixString(16)
          .padLeft(2, '0');
      test('text: ${entry.key}', () {
        expect(toHex(encodeText(text)), '01${lengthHex}000000$bytesHex');
      });
      test('set-clipboard: ${entry.key}', () {
        expect(
          toHex(encodeSetClipboard(text: text)),
          '090000000000000000010000'
          '00$lengthHex$bytesHex',
        );
      });
    }
  });

  group('argument validation', () {
    test('rejects video sizes beyond 16 bits', () {
      expect(
        () => encodeHover(videoWidth: 65536, videoHeight: 1, x: 0, y: 0),
        throwsRangeError,
      );
    });

    test('rejects non-finite coordinates', () {
      expect(
        () => encodeHover(videoWidth: 1, videoHeight: 1, x: double.nan, y: 0),
        throwsArgumentError,
      );
    });

    test('rejects pointer ids beyond 2^53', () {
      expect(
        () => encodeTouch(
          action: 0,
          pointerId: 9007199254740993,
          videoWidth: 1,
          videoHeight: 1,
          x: 0,
          y: 0,
        ),
        throwsRangeError,
      );
    });
  });
}
