// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

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
    this.videoCodec = VideoCodec.automatic,
  });

  /// Whether the device audio starts silent. Change it with `setMuted`.
  final bool muted;

  /// Video codec preference for each connection.
  final VideoCodec videoCodec;
}
