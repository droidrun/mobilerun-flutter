// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

List<String> ordered(List<String> mimeTypes) => [
  for (final i in videoCodecOrder(mimeTypes)) mimeTypes[i],
];

void main() {
  test('default order is VP9, H.265, H.264, then the rest, stably', () {
    expect(
      ordered([
        'video/VP8',
        'video/H264',
        'video/rtx',
        'video/H265',
        'video/AV1',
        'video/VP9',
        'video/H264',
        'video/red',
      ]),
      [
        'video/VP9',
        'video/H265',
        'video/H264',
        'video/H264',
        'video/VP8',
        'video/rtx',
        'video/AV1',
        'video/red',
      ],
    );
  });

  test('HEVC is recognised as H.265 and AVC as H.264', () {
    expect(ordered(['video/avc', 'video/hevc']), ['video/hevc', 'video/avc']);
  });

  test('without an H.265 decoder only H.264 (and rtx) is offered', () {
    expect(
      ordered([
        'video/VP8',
        'video/VP9',
        'video/H264',
        'video/rtx',
        'video/H264',
        'video/AV1',
      ]),
      ['video/H264', 'video/rtx', 'video/H264'],
    );
  });

  test('without H.265 and H.264 the default order is kept', () {
    expect(ordered(['video/VP8', 'video/VP9']), ['video/VP9', 'video/VP8']);
  });

  test('an empty capability list stays empty', () {
    expect(videoCodecOrder(const []), isEmpty);
  });
}
