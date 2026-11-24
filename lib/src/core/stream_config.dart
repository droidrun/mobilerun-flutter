// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'publish.dart';

/// Video codecs offered to the device.
enum VideoCodec {
  /// Prefer VP9, H.265, then H.264; use H.264 when H.265 is unavailable.
  automatic,

  /// Offer H.264 and its auxiliary codecs only.
  h264Only,
}

/// Options of a [DeviceStreamSession].
final class StreamConfig {
  /// Creates a configuration.
  const StreamConfig({
    this.muted = true,
    this.publishCapabilities,
    this.videoCodec = VideoCodec.automatic,
  });

  /// Whether the device audio starts silent. Change it with `setMuted`.
  final bool muted;

  /// Device support snapshot for first-offer upstream reservations.
  /// Changing it requires a new session and fresh stream token.
  final DevicePublishCapabilities? publishCapabilities;

  /// Video codec preference for each connection.
  final VideoCodec videoCodec;
}
