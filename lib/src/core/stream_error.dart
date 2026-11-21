// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Why a connection attempt failed, as reported to `onError`.
///
/// [code] is the snake_case name shared by every Mobilerun stream SDK.
enum StreamErrorReason {
  /// The token provider threw, returned a blank key or exceeded its deadline.
  credentialsUnavailable('credentials_unavailable'),

  /// The signalling socket could not be opened or closed before it opened:
  /// an unreachable host, a wrong device or a refused origin. A used or
  /// expired token also lands here unless the platform exposes HTTP 401.
  connectionRefused('connection_refused'),

  /// The upgrade was refused with HTTP 401 or 403: the key was invalid,
  /// expired or already used.
  tokenRejected('token_rejected'),

  /// A session that was open dropped, including the server session cap.
  disconnected('disconnected'),

  /// The server reported the device offline or not ready. Reserved: the
  /// current protocol has no such message, so this is not produced yet.
  deviceUnavailable('device_unavailable'),

  /// Anything else, such as a watchdog timeout or a negotiation failure.
  unknown('unknown');

  const StreamErrorReason(this.code);

  /// The shared snake_case name, for example `connection_refused`.
  final String code;
}

/// One failed connection attempt, delivered to `DeviceStreamSession.onError`.
final class StreamError {
  /// Creates an error.
  const StreamError({
    required this.reason,
    required this.message,
    required this.attempt,
    required this.isFinal,
  });

  /// Why the attempt failed.
  final StreamErrorReason reason;

  /// A short description. It never contains the URL or a token.
  final String message;

  /// The 1-based number of consecutive failed attempts so far.
  final int attempt;

  /// True when the SDK stops retrying. The stream is then unavailable until
  /// `DeviceStreamSession.retry`.
  final bool isFinal;

  @override
  String toString() =>
      'StreamError(${reason.code}, attempt: $attempt, final: $isFinal)';
}

/// Receives every failed connection attempt of a session.
typedef StreamErrorCallback = void Function(StreamError error);
