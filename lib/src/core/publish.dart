// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

import 'stream_error.dart';

/// Device support supplied by the integrator's backend capabilities response.
/// This snapshot does not grant the viewer permission to publish.
@immutable
final class DevicePublishCapabilities {
  /// Creates a device support snapshot. Only the `direct` transport is supported.
  const DevicePublishCapabilities({
    required this.microphoneInjection,
    required this.cameraInjection,
    this.mediaInjectionTransport,
  });

  /// Whether the device supports microphone injection.
  final bool microphoneInjection;

  /// Whether the device supports camera injection.
  final bool cameraInjection;

  /// Injection transport reported by the device service.
  final String? mediaInjectionTransport;

  /// Whether microphone publication is supported by this snapshot.
  bool get supportsMicrophone =>
      microphoneInjection && mediaInjectionTransport == 'direct';
}

/// Inputs requested for one publication. Audio is required and must be true.
@immutable
final class PublishOptions {
  /// Creates a request; video defaults to false.
  const PublishOptions({required this.audio, this.video = false});

  /// Must be true; video-only requests fail before capture.
  final bool audio;

  /// Whether to include the default camera with the microphone.
  final bool video;
}

/// Local input kinds, in audio then video wire order.
enum PublishKind {
  /// Default microphone.
  audio,

  /// Default camera.
  video,
}

/// Publication lifecycle, independent from the viewer connection status.
enum PublishPhase {
  /// No publication has been requested.
  idle,

  /// Admitted; waiting for local permissions and inputs, still detached.
  capturing,

  /// Start sent; awaiting server admission.
  starting,

  /// Admitted; attaching inputs and awaiting injection.
  accepted,

  /// All inputs attached and injection confirmed by the server.
  active,

  /// Explicitly stopped locally.
  stopped,

  /// Publication failed and its resources were released.
  error,
}

/// Structured publication failure. Branch on [reason], not [message].
@immutable
final class PublishFailure {
  /// Creates a failure using the shared SDK reason names.
  const PublishFailure({
    required this.reason,
    required this.message,
    this.detail,
    this.serverReason,
  });

  /// Normalized reason; [StreamErrorReason.code] has the shared wire spelling.
  final StreamErrorReason reason;

  /// Safe display description, without platform error contents or credentials.
  final String message;

  /// Machine-readable diagnostic, when applicable.
  final String? detail;

  /// Original string reason supplied by the server.
  final String? serverReason;
}

/// A failed or cancelled call to `DeviceStreamSession.startPublish`.
final class PublishException implements Exception {
  /// Creates an exception carrying [failure].
  const PublishException(this.failure);

  /// Structured failure, also used by state and the error observer.
  final PublishFailure failure;

  @override
  String toString() =>
      'PublishException(${failure.reason.code}, ${failure.detail})';
}

/// Immutable publication snapshot, replayed by the session's ValueListenable.
@immutable
final class PublishState {
  /// Creates a snapshot, defensively copying [kinds].
  PublishState({
    this.phase = PublishPhase.idle,
    this.mediaSessionId,
    List<PublishKind> kinds = const [],
    this.reason,
    this.message,
    this.detail,
    this.serverReason,
  }) : kinds = List.unmodifiable(kinds);

  /// Current publication phase.
  final PublishPhase phase;

  /// Publication UUID, distinct from the viewer session; null before signaling.
  final String? mediaSessionId;

  /// Requested inputs in canonical order.
  final List<PublishKind> kinds;

  /// Shared snake_case failure reason, or `stopped_by_client` on explicit stop.
  final String? reason;

  /// Failure description, when present.
  final String? message;

  /// Structured diagnostic, when present.
  final String? detail;

  /// Original server reason, when present.
  final String? serverReason;
}
