// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// English defaults shared with the React UI; replace any string for i18n.
final class StreamLabels {
  /// Creates values with individually overridable defaults.
  const StreamLabels({
    this.paymentCardTitle = 'Approve payment',
    this.waiting = 'Waiting for approval',
    this.card = 'Card',
    this.app = 'App',
    this.domain = 'Domain',
    this.timeLeft = '{time} left',
    this.expired = 'Approval expired',
    this.approve = 'Approve',
    this.deny = 'Deny',
    this.viewSwitch = 'Approval view',
    this.details = 'Details',
    this.device = 'Device',
    this.connecting = 'connecting',
    this.reconnecting = 'reconnecting',
    this.reconnectingAttempt = 'reconnecting ({attempt}/{max})',
    this.unavailable = 'device stream unavailable',
    this.retry = 'Retry',
    this.back = 'Back',
    this.home = 'Home',
    this.recent = 'Recent',
  });

  /// paymentCardTitle label.
  final String paymentCardTitle;

  /// waiting label.
  final String waiting;

  /// card label.
  final String card;

  /// app label.
  final String app;

  /// domain label.
  final String domain;

  /// timeLeft label.
  final String timeLeft;

  /// expired label.
  final String expired;

  /// approve label.
  final String approve;

  /// deny label.
  final String deny;

  /// viewSwitch label.
  final String viewSwitch;

  /// details label.
  final String details;

  /// device label.
  final String device;

  /// connecting label.
  final String connecting;

  /// reconnecting label.
  final String reconnecting;

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

  /// Returns a copy with the supplied values replaced.
  StreamLabels copyWith({
    String? paymentCardTitle,
    String? waiting,
    String? card,
    String? app,
    String? domain,
    String? timeLeft,
    String? expired,
    String? approve,
    String? deny,
    String? viewSwitch,
    String? details,
    String? device,
    String? connecting,
    String? reconnecting,
    String? reconnectingAttempt,
    String? unavailable,
    String? retry,
    String? back,
    String? home,
    String? recent,
  }) => StreamLabels(
    paymentCardTitle: paymentCardTitle ?? this.paymentCardTitle,
    waiting: waiting ?? this.waiting,
    card: card ?? this.card,
    app: app ?? this.app,
    domain: domain ?? this.domain,
    timeLeft: timeLeft ?? this.timeLeft,
    expired: expired ?? this.expired,
    approve: approve ?? this.approve,
    deny: deny ?? this.deny,
    viewSwitch: viewSwitch ?? this.viewSwitch,
    details: details ?? this.details,
    device: device ?? this.device,
    connecting: connecting ?? this.connecting,
    reconnecting: reconnecting ?? this.reconnecting,
    reconnectingAttempt: reconnectingAttempt ?? this.reconnectingAttempt,
    unavailable: unavailable ?? this.unavailable,
    retry: retry ?? this.retry,
    back: back ?? this.back,
    home: home ?? this.home,
    recent: recent ?? this.recent,
  );
}
