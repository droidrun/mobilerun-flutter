// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// A stream request could not be completed.
sealed class StreamException implements Exception {
  const StreamException._(this.message);

  /// A short description of the failure.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// There is no active stream connection.
final class StreamNotConnectedException extends StreamException {
  /// Created by the SDK.
  @internal
  const StreamNotConnectedException() : super._('Stream is not connected');
}

/// The connection was lost during a request.
final class StreamDisconnectedException extends StreamException {
  /// Created by the SDK.
  @internal
  const StreamDisconnectedException() : super._('Stream disconnected');
}

/// The screenshot request failed.
final class ScreenshotFailedException extends StreamException {
  /// Created by the SDK.
  @internal
  const ScreenshotFailedException([super.message = 'Screenshot failed'])
    : super._();
}

/// The screenshot did not arrive before its timeout.
final class ScreenshotTimeoutException extends StreamException {
  /// Created by the SDK.
  @internal
  const ScreenshotTimeoutException() : super._('Screenshot timed out');
}
