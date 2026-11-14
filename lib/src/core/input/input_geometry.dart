// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal input implementation; not exported by the package.
// ignore_for_file: public_member_api_docs

import 'dart:ui';

/// Aspect-fit geometry in displayed (post-rotation) video pixels.
final class InputGeometry {
  InputGeometry(Size view, int width, int height, {int rotation = 0})
    : videoWidth = rotation % 180 == 0 ? width : height,
      videoHeight = rotation % 180 == 0 ? height : width {
    final video = Size(videoWidth.toDouble(), videoHeight.toDouble());
    if (view.isEmpty || video.isEmpty) {
      rect = Rect.zero;
      return;
    }
    final scale = view.width / video.width < view.height / video.height
        ? view.width / video.width
        : view.height / video.height;
    rect = Rect.fromCenter(
      center: view.center(Offset.zero),
      width: video.width * scale,
      height: video.height * scale,
    );
  }

  final int videoWidth;
  final int videoHeight;
  late final Rect rect;

  Offset? map(Offset point) {
    if (rect.isEmpty ||
        !point.dx.isFinite ||
        !point.dy.isFinite ||
        point.dx < rect.left ||
        point.dx > rect.right ||
        point.dy < rect.top ||
        point.dy > rect.bottom) {
      return null;
    }
    return Offset(
      ((point.dx - rect.left) / rect.width * videoWidth)
          .clamp(0, videoWidth)
          .toDouble(),
      ((point.dy - rect.top) / rect.height * videoHeight)
          .clamp(0, videoHeight)
          .toDouble(),
    );
  }
}
