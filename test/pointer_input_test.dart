// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/core/input/input_geometry.dart';
import 'package:mobilerun_flutter/src/core/input/pointer_input.dart';

void main() {
  late List<Uint8List> sent;
  late PointerInput input;
  final geometry = InputGeometry(const Size(400, 400), 200, 400);
  int slot(Uint8List bytes) => ByteData.sublistView(bytes).getInt64(2);
  setUp(() {
    sent = [];
    input = PointerInput(sent.add);
  });
  test('ten stable slots, reject eleventh, reuse released slot', () {
    for (var i = 0; i < 10; i++) {
      expect(input.down(i + 100, const Offset(200, 200), geometry), isTrue);
    }
    expect(sent.map(slot), orderedEquals(List.generate(10, (i) => i)));
    expect(input.down(999, const Offset(200, 200), geometry), isFalse);
    input.up(103);
    input.down(999, const Offset(200, 200), geometry);
    expect(slot(sent.last), 3);
  });
  test('mouse has id -1 independently of touch slots', () {
    input.down(3, const Offset(200, 200), geometry, mouse: true);
    input.down(4, const Offset(200, 200), geometry);
    expect(sent.map(slot), [-1, 0]);
  });
  test('outside DOWN is ignored and never gains an active pointer', () {
    input.down(1, const Offset(0, 0), geometry);
    input.move(1, const Offset(200, 200));
    input.up(1);
    expect(sent, isEmpty);
  });
  test(
    'moves coalesce per finger, outside move ignored, UP uses latest point',
    () {
      input.down(11, const Offset(200, 200), geometry);
      input.down(12, const Offset(200, 200), geometry);
      input.move(11, const Offset(210, 210));
      input.move(11, const Offset(220, 220));
      input.move(12, const Offset(230, 230));
      input.flushMoves();
      input.flushMoves();
      expect(sent.map((b) => b[1]), [0, 0, 2, 2]);
      input.move(11, const Offset(240, 240));
      input.move(11, Offset.zero);
      input.up(11);
      expect(ByteData.sublistView(sent.last).getInt32(10, Endian.little), 140);
      expect(sent.last[1], 1);
      input.cancel();
      expect(sent.last[1], 3);
      expect(slot(sent.last), 1);
      input.flushMoves();
      expect(sent.length, 6);
      expect(
        ByteData.sublistView(sent.last).getUint16(22, Endian.little),
        65535,
      );
      expect(ByteData.sublistView(sent.last).getInt32(28, Endian.little), 1);
    },
  );
  test('display only reset sends no releases', () {
    input.down(1, const Offset(200, 200), geometry);
    input.reset();
    input.up(1);
    input.cancel();
    expect(sent.length, 1);
  });
}
