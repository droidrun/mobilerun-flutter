// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// English defaults shared with React; override individual strings for i18n.
final class TaskApprovalLabels {
  /// Creates labels with individually overridable defaults.
  const TaskApprovalLabels({
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

  /// Returns a copy with selected labels replaced.
  TaskApprovalLabels copyWith({
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
  }) => TaskApprovalLabels(
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
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskApprovalLabels &&
          other.paymentCardTitle == paymentCardTitle &&
          other.waiting == waiting &&
          other.card == card &&
          other.app == app &&
          other.domain == domain &&
          other.timeLeft == timeLeft &&
          other.expired == expired &&
          other.approve == approve &&
          other.deny == deny &&
          other.viewSwitch == viewSwitch &&
          other.details == details &&
          other.device == device;

  @override
  int get hashCode => Object.hashAll([
    paymentCardTitle,
    waiting,
    card,
    app,
    domain,
    timeLeft,
    expired,
    approve,
    deny,
    viewSwitch,
    details,
    device,
  ]);
}
