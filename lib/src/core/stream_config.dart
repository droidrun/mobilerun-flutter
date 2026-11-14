// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Options of a [DeviceStreamSession].
final class StreamConfig {
  /// Creates a configuration.
  const StreamConfig({this.muted = true, this.zeroPlayoutDelay = true});

  /// Whether the device audio starts silent; change it later with
  /// [DeviceStreamSession.setMuted]. The audio track is negotiated either way
  /// (the server expects it); it is only disabled.
  final bool muted;

  /// Whether the jitter buffer targets zero playout delay: a little less
  /// smoothness for noticeably lower touch latency.
  ///
  /// The underlying WebRTC setting is process-wide and fixed by the first
  /// initialisation of `flutter_webrtc`, which creating a video renderer
  /// already triggers. To get it, call
  /// `WebRTC.initialize(options: {'zeroPlayoutDelay': true})` in `main()`
  /// before the first renderer; a session started later cannot change it.
  final bool zeroPlayoutDelay;
}
