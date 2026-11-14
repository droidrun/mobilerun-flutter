// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Thrown when a session request (a screenshot) cannot be served.
final class StreamSessionException implements Exception {
  /// Creates the exception with a human readable [message].
  const StreamSessionException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'StreamSessionException: $message';
}
