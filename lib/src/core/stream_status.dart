// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

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

/// All attempts failed. Only [DeviceStreamSession.retry] starts a new cycle.
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
  const VideoSize(this.width, this.height);

  /// Frame width in pixels.
  final int width;

  /// Frame height in pixels.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is VideoSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'VideoSize(${width}x$height)';
}
