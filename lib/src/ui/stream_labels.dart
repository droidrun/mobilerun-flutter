// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// English defaults shared with React; override individual strings for i18n.
final class StreamLabels {
  /// Creates labels with individually overridable defaults.
  const StreamLabels({
    this.connecting = 'connecting',
    this.reconnecting = 'reconnecting',
    this.disconnected = 'disconnected',
    this.reconnectingAttempt = 'reconnecting ({attempt}/{max})',
    this.unavailable = 'device stream unavailable',
    this.retry = 'Retry',
    this.back = 'Back',
    this.home = 'Home',
    this.recent = 'Recent',
    this.microphone = 'Microphone',
    this.camera = 'Camera',
    this.stopMicrophone = 'Stop microphone',
    this.stopCamera = 'Stop camera',
    this.publishStarting = 'Starting inputs',
    this.publishPermissionDenied = 'Microphone or camera permission denied',
    this.publishNotAllowed = 'Publishing is not allowed',
    this.publishFailed = 'Could not publish inputs',
  });

  /// connecting label.
  final String connecting;

  /// reconnecting label.
  final String reconnecting;

  /// Shown while reconnecting after an open session dropped.
  final String disconnected;

  /// reconnectingAttempt label.
  final String reconnectingAttempt;

  /// unavailable label.
  final String unavailable;

  /// retry label.
  final String retry;

  /// back label.
  final String back;

  /// home label.
  final String home;

  /// recent label.
  final String recent;

  /// Microphone.
  final String microphone;

  /// Camera.
  final String camera;

  /// Stop microphone.
  final String stopMicrophone;

  /// Stop camera.
  final String stopCamera;

  /// Starting inputs.
  final String publishStarting;

  /// Microphone or camera permission denied.
  final String publishPermissionDenied;

  /// Publishing is not allowed.
  final String publishNotAllowed;

  /// Could not publish inputs.
  final String publishFailed;

  /// Returns a copy with selected labels replaced.
  StreamLabels copyWith({
    String? connecting,
    String? reconnecting,
    String? disconnected,
    String? reconnectingAttempt,
    String? unavailable,
    String? retry,
    String? back,
    String? home,
    String? recent,
    String? microphone,
    String? camera,
    String? stopMicrophone,
    String? stopCamera,
    String? publishStarting,
    String? publishPermissionDenied,
    String? publishNotAllowed,
    String? publishFailed,
  }) => StreamLabels(
    connecting: connecting ?? this.connecting,
    reconnecting: reconnecting ?? this.reconnecting,
    disconnected: disconnected ?? this.disconnected,
    reconnectingAttempt: reconnectingAttempt ?? this.reconnectingAttempt,
    unavailable: unavailable ?? this.unavailable,
    retry: retry ?? this.retry,
    back: back ?? this.back,
    home: home ?? this.home,
    recent: recent ?? this.recent,
    microphone: microphone ?? this.microphone,
    camera: camera ?? this.camera,
    stopMicrophone: stopMicrophone ?? this.stopMicrophone,
    stopCamera: stopCamera ?? this.stopCamera,
    publishStarting: publishStarting ?? this.publishStarting,
    publishPermissionDenied:
        publishPermissionDenied ?? this.publishPermissionDenied,
    publishNotAllowed: publishNotAllowed ?? this.publishNotAllowed,
    publishFailed: publishFailed ?? this.publishFailed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamLabels &&
          other.connecting == connecting &&
          other.reconnecting == reconnecting &&
          other.disconnected == disconnected &&
          other.reconnectingAttempt == reconnectingAttempt &&
          other.unavailable == unavailable &&
          other.retry == retry &&
          other.back == back &&
          other.home == home &&
          other.recent == recent &&
          other.microphone == microphone &&
          other.camera == camera &&
          other.stopMicrophone == stopMicrophone &&
          other.stopCamera == stopCamera &&
          other.publishStarting == publishStarting &&
          other.publishPermissionDenied == publishPermissionDenied &&
          other.publishNotAllowed == publishNotAllowed &&
          other.publishFailed == publishFailed;

  @override
  int get hashCode => Object.hashAll([
    connecting,
    reconnecting,
    disconnected,
    reconnectingAttempt,
    unavailable,
    retry,
    back,
    home,
    recent,
    microphone,
    camera,
    stopMicrophone,
    stopCamera,
    publishStarting,
    publishPermissionDenied,
    publishNotAllowed,
    publishFailed,
  ]);
}
