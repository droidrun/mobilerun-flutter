// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// Where a [DeviceStreamSession] is in its connect and reconnect cycle.
sealed class StreamStatus {
  const StreamStatus();
}

/// The first attempt is in flight.
final class StreamConnecting extends StreamStatus {
  /// Creates the status.
  const StreamConnecting();

  @override
  bool operator ==(Object other) => other is StreamConnecting;

  @override
  int get hashCode => (StreamConnecting).hashCode;

  @override
  String toString() => 'StreamConnecting';
}

/// The peer connection is up.
final class StreamConnected extends StreamStatus {
  /// Creates the status.
  const StreamConnected();

  @override
  bool operator ==(Object other) => other is StreamConnected;

  @override
  int get hashCode => (StreamConnected).hashCode;

  @override
  String toString() => 'StreamConnected';
}

/// An attempt failed; the next one is waiting out its backoff or running.
final class StreamReconnecting extends StreamStatus {
  /// Creates the status for the 1-based reconnect [attempt].
  const StreamReconnecting(this.attempt);

  /// The 1-based number of the upcoming or in-flight reconnect attempt, out of
  /// [ReconnectPolicy.maxAttempts]; 0 right after [DeviceStreamSession.retry].
  final int attempt;

  @override
  bool operator ==(Object other) =>
      other is StreamReconnecting && other.attempt == attempt;

  @override
  int get hashCode => Object.hash(StreamReconnecting, attempt);

  @override
  String toString() => 'StreamReconnecting($attempt)';
}

/// Automatic retrying stopped. Retry, foreground wake or network return
/// can start a new cycle.
final class StreamUnavailable extends StreamStatus {
  /// Creates the status.
  const StreamUnavailable();

  @override
  bool operator ==(Object other) => other is StreamUnavailable;

  @override
  int get hashCode => (StreamUnavailable).hashCode;

  @override
  String toString() => 'StreamUnavailable';
}

/// The size of the decoded device video.
final class VideoSize {
  /// Creates a size of [width] by [height] pixels.
  @internal
  const VideoSize(this.width, this.height, {this.rotation = 0});

  /// Frame width in pixels.
  final int width;

  /// Frame height in pixels.
  final int height;

  /// Clockwise video rotation in degrees.
  /// Zero unless a DeviceStreamView renders this session.
  final int rotation;

  @override
  bool operator ==(Object other) =>
      other is VideoSize &&
      other.width == width &&
      other.height == height &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(width, height, rotation);

  @override
  String toString() => 'VideoSize(${width}x$height, rotation: $rotation)';
}
