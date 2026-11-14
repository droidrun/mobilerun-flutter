// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/core/input/input_geometry.dart';

void main() {
  test('portrait: centered letterbox and inclusive video edges', () {
    final geometry = InputGeometry(const Size(400, 400), 200, 400);
    expect(geometry.rect, const Rect.fromLTWH(100, 0, 200, 400));
    expect(geometry.map(const Offset(200, 200)), const Offset(100, 200));
    expect(geometry.map(const Offset(100, 0)), Offset.zero);
    expect(geometry.map(const Offset(300, 400)), const Offset(200, 400));
    expect(geometry.map(const Offset(99, 100)), isNull);
    expect(geometry.map(const Offset(301, 100)), isNull);
  });
  test('landscape: horizontal bands do not receive DOWN', () {
    final geometry = InputGeometry(const Size(400, 400), 400, 200);
    expect(geometry.rect, const Rect.fromLTWH(0, 100, 400, 200));
    expect(geometry.map(const Offset(200, 100)), const Offset(200, 0));
    expect(geometry.map(const Offset(200, 99)), isNull);
  });
  for (final rotation in [0, 90, 180, 270]) {
    test(
      'rotation $rotation maps displayed pixels without a second rotation',
      () {
        final g = InputGeometry(
          const Size(600, 600),
          200,
          400,
          rotation: rotation,
        );
        final swapped = rotation % 180 != 0;
        expect(g.videoWidth, swapped ? 400 : 200);
        expect(g.videoHeight, swapped ? 200 : 400);
        expect(
          g.map(g.rect.bottomRight),
          Offset(g.videoWidth.toDouble(), g.videoHeight.toDouble()),
        );
      },
    );
  }
  test('zero size and nonfinite coordinates are ignored', () {
    expect(InputGeometry(Size.zero, 200, 400).map(Offset.zero), isNull);
    expect(InputGeometry(const Size(400, 400), 0, 0).map(Offset.zero), isNull);
    expect(
      InputGeometry(
        const Size(400, 400),
        200,
        400,
      ).map(const Offset(double.nan, 10)),
      isNull,
    );
  });
}
