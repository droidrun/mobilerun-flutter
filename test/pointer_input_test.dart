// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/core/input/input_geometry.dart';
import 'package:mobilerun_flutter/src/core/input/pointer_input.dart';
import 'package:mobilerun_flutter/src/protocol/control_messages.dart';

void main() {
  late List<Uint8List> sent;
  late PointerInput input;
  final geometry = InputGeometry(const Size(400, 400), 200, 400);
  Uint8List touch(int action, int slot, [double x = 100, double y = 200]) =>
      encodeTouch(
        action: action,
        pointerId: slot,
        videoWidth: 200,
        videoHeight: 400,
        x: x,
        y: y,
        pressure: 1,
        actionButton: 1,
        buttons: 1,
      );
  setUp(() {
    sent = [];
    input = PointerInput(sent.add);
  });
  test('ten stable slots reject the eleventh and reuse a released slot', () {
    for (var i = 0; i < 10; i++) {
      expect(input.down(i + 100, const Offset(200, 200), geometry), isTrue);
    }
    expect(input.down(999, const Offset(200, 200), geometry), isFalse);
    input.up(103);
    input.down(999, const Offset(200, 200), geometry);
    expect(sent, [
      for (var i = 0; i < 10; i++) touch(0, i),
      touch(1, 3),
      touch(0, 3),
    ]);
  });
  test('mouse has id -1 independently of touch slots', () {
    input.down(3, const Offset(200, 200), geometry, mouse: true);
    input.down(4, const Offset(200, 200), geometry);
    expect(sent, [touch(0, -1), touch(0, 0)]);
  });
  test('outside DOWN never gains an active pointer', () {
    input.down(1, Offset.zero, geometry);
    input.move(1, const Offset(200, 200));
    input.up(1);
    expect(sent, isEmpty);
  });
  test('MOVE coalesces per finger and ignores outside points', () {
    input.down(11, const Offset(200, 200), geometry);
    input.down(12, const Offset(200, 200), geometry);
    input.move(11, const Offset(210, 210));
    input.move(11, const Offset(220, 220));
    input.move(12, const Offset(230, 230));
    input.flushMoves();
    input.flushMoves();
    input.move(11, const Offset(240, 240));
    input.move(11, Offset.zero);
    input.up(11);
    input.cancel();
    input.flushMoves();
    expect(sent, [
      touch(0, 0),
      touch(0, 1),
      touch(2, 0, 120, 220),
      touch(2, 1, 130, 230),
      touch(1, 0, 140, 240),
      touch(3, 1, 130, 230),
    ]);
  });
  test('cancel releases each active slot exactly once with CANCEL', () {
    input.down(1, const Offset(200, 200), geometry);
    input.down(2, const Offset(250, 300), geometry);
    input.cancel();
    input.up(1);
    input.cancel();
    expect(sent, [
      touch(0, 0),
      touch(0, 1, 150, 300),
      touch(3, 0),
      touch(3, 1, 150, 300),
    ]);
  });
}
