// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Options of a [DeviceStreamSession].
final class StreamConfig {
  /// Creates a configuration.
  const StreamConfig({this.muted = true, this.zeroPlayoutDelay = true});

  /// Whether the device audio stays silent. The audio track is still
  /// negotiated (the server expects it); it is only disabled.
  final bool muted;

  /// Whether the jitter buffer targets zero playout delay: a little less
  /// smoothness for noticeably lower touch latency.
  ///
  /// The underlying WebRTC field trial is process-wide and read once, when
  /// the first peer connection of the process is created. A later session with
  /// a different value does not change it.
  final bool zeroPlayoutDelay;
}
