// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal input implementation; not exported by the package.
// ignore_for_file: public_member_api_docs

import 'dart:ui';
import 'dart:typed_data';
import 'input_geometry.dart';
import '../../protocol/control_messages.dart';

/// Flutter scroll deltas are pixels; the S1 encoder applies ticks / 16.
Offset scrollTicks(Offset delta) => delta * -0.01;

/// Routes upright positions and abstract ticks, ignoring invalid/outside points.
void routeScroll({
  required InputGeometry geometry,
  required Offset position,
  required Offset ticks,
  required void Function(Uint8List) send,
  int buttons = 0,
}) {
  final point = geometry.map(position);
  if (point == null) return;
  send(
    encodeScroll(
      videoWidth: geometry.videoWidth,
      videoHeight: geometry.videoHeight,
      x: point.dx,
      y: point.dy,
      hscrollTicks: ticks.dx,
      vscrollTicks: ticks.dy,
      buttons: buttons,
    ),
  );
}
