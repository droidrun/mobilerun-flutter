// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Why a connection attempt failed, as reported to `onError`.
///
/// [code] is the snake_case name shared by every Mobilerun stream SDK.
enum StreamErrorReason {
  /// The token provider threw, returned a blank stream token or exceeded
  /// its deadline.
  credentialsUnavailable('credentials_unavailable'),

  /// The signalling socket could not be opened or closed before it opened:
  /// an unreachable host, a wrong device or a refused origin. A used or
  /// expired token also lands here unless the platform exposes HTTP 401.
  connectionRefused('connection_refused'),

  /// The upgrade was refused with HTTP 401: the stream token was invalid, expired or
  /// already used. HTTP 403 is [connectionRefused].
  tokenRejected('token_rejected'),

  /// A session that was open dropped, including the server session cap.
  disconnected('disconnected'),

  /// The server reported the device offline or not ready. Reserved: the
  /// current protocol has no such message, so this is not produced yet.
  deviceUnavailable('device_unavailable'),

  /// Anything else, such as a watchdog timeout or a negotiation failure.
  unknown('unknown'),

  /// The server refused this viewer's publication.
  publishNotAllowed('publish_not_allowed'),

  /// The device or local implementation cannot publish the requested inputs.
  publishUnsupported('publish_unsupported'),

  /// Local microphone/camera permission was denied or restricted.
  permissionDenied('permission_denied'),

  /// Another viewer already owns the device's publication lease.
  publishBusy('publish_busy'),

  /// Capture, attachment or injection failed.
  publishFailed('publish_failed'),

  /// Admission succeeded but injection did not become active in time.
  publishTimeout('publish_timeout'),

  /// Explicit local cancellation, used by the pending method only.
  publishCancelled('publish_cancelled');

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
    this.operation,
    this.mediaSessionId,
    this.detail,
    this.serverReason,
  });

  /// Why the attempt failed.
  final StreamErrorReason reason;

  /// A short description. It never contains the URL or a token.
  final String message;

  /// The 1-based number of consecutive failed attempts so far.
  final int attempt;

  /// True when the SDK stopped retrying. Retry, foreground wake or network
  /// return can start a new cycle from unavailable.
  final bool isFinal;

  /// `publish` for a publication failure; null for connection errors.
  final String? operation;

  /// Publication UUID, only after a start reached signaling.
  final String? mediaSessionId;

  /// Machine-readable publication diagnostic.
  final String? detail;

  /// Original server publication reason.
  final String? serverReason;

  @override
  String toString() =>
      'StreamError(${reason.code}, attempt: $attempt, final: $isFinal)';
}

/// Receives every failed connection attempt of a session.
typedef StreamErrorCallback = void Function(StreamError error);
