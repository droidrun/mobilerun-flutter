// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

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
    pressure: _num(a, 'pressure').toDouble(),
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
  'text': (a) => encodeText(text: a['text']! as String),
  'set-clipboard': (a) => encodeSetClipboard(
    text: a['text']! as String,
    paste: a['paste']! as bool,
  ),
};

void main() {
  final counter = CaseCounter();
  var total = 0;

  for (final entry in _encoders.entries) {
    final cases = readCases('control/${entry.key}.json');
    total += cases.length;
    group('control/${entry.key}', () {
      for (final fixtureCase in cases) {
        test(fixtureCase['name']! as String, () {
          final args = (fixtureCase['args']! as Map).cast<String, Object?>();
          expect(toHex(entry.value(args)), fixtureCase['hex']);
          counter.hit();
        });
      }
    });
  }

  test('every control fixture case was exercised', () {
    expect(total, greaterThan(0));
    expect(counter.executed, total);
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
