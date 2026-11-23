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
          other.recent == recent;

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
  ]);
}
