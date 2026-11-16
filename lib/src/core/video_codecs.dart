// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'stream_config.dart';

bool _isH265(String mimeType) {
  final mime = mimeType.toLowerCase();
  return mime.contains('h265') || mime.contains('hevc');
}

bool _isH264(String mimeType) {
  final mime = mimeType.toLowerCase();
  return mime.contains('h264') || mime.contains('avc');
}

bool _isAuxiliary(String mimeType) {
  final mime = mimeType.toLowerCase();
  return mime.endsWith('/rtx') ||
      mime.endsWith('/red') ||
      mime.endsWith('/ulpfec') ||
      mime.contains('/flexfec');
}

int _priority(String mimeType) {
  final mime = mimeType.toLowerCase();
  if (mime.contains('vp9')) return 1;
  if (_isH265(mime)) return 2;
  if (_isH264(mime)) return 3;
  return 4;
}

/// The order in which a receiver should offer its video codecs, as indices
/// into [mimeTypes] (the receiver capabilities).
///
/// Default: VP9, then H.265, then H.264, then everything else, each group in
/// its original order (the server picks H.265 when it is offered).
///
/// When the receiver has no H.265 decoder the offer shrinks to H.264 plus the
/// auxiliary entries (rtx, red, ulpfec, flexfec), the one other hardware
/// accelerated codec every platform has. If there is no H.264 either, the
/// default order is kept. [preference] can restrict the offer to H.264; when
/// H.264 is unavailable, that preference keeps the platform default order.
List<int> videoCodecOrder(
  List<String> mimeTypes, {
  VideoCodec preference = VideoCodec.automatic,
}) {
  final indices = List<int>.generate(mimeTypes.length, (i) => i);
  if (preference == VideoCodec.h264Only && !mimeTypes.any(_isH264)) {
    return indices;
  }
  if (preference == VideoCodec.h264Only ||
      (!mimeTypes.any(_isH265) && mimeTypes.any(_isH264))) {
    return [
      for (final i in indices)
        if (_isH264(mimeTypes[i]) || _isAuxiliary(mimeTypes[i])) i,
    ];
  }
  // A stable sort: Dart's List.sort is not guaranteed to be.
  return [
    for (final priority in const [1, 2, 3, 4])
      for (final i in indices)
        if (_priority(mimeTypes[i]) == priority) i,
  ];
}
