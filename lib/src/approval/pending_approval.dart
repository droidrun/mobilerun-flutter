// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// A human approval returned by the integrator's backend.
final class PendingApproval {
  /// Creates an approval. Unknown kinds are intentionally accepted.
  const PendingApproval({
    required this.approvalId,
    required this.kind,
    this.details = const {},
    required this.expiresAt,
    this.deviceId,
  });

  /// Backend approval identifier.
  final String approvalId;

  /// Approval kind, currently `payment_card`.
  final String kind;

  /// Kind-specific display fields.
  final Map<String, Object?> details;

  /// ISO 8601 expiry. It is only used for display.
  final String expiresAt;

  /// Optional device associated with this approval.
  final String? deviceId;

  /// Returns a copy with the supplied fields replaced.
  PendingApproval copyWith({
    String? approvalId,
    String? kind,
    Map<String, Object?>? details,
    String? expiresAt,
    String? deviceId,
    bool clearDeviceId = false,
  }) => PendingApproval(
    approvalId: approvalId ?? this.approvalId,
    kind: kind ?? this.kind,
    details: details ?? this.details,
    expiresAt: expiresAt ?? this.expiresAt,
    deviceId: clearDeviceId ? null : deviceId ?? this.deviceId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingApproval &&
          approvalId == other.approvalId &&
          kind == other.kind &&
          expiresAt == other.expiresAt &&
          deviceId == other.deviceId &&
          _detailsEqual(details, other.details);

  @override
  int get hashCode =>
      Object.hash(approvalId, kind, expiresAt, deviceId, _detailsHash(details));
}

/// The decision forwarded to the backend. Expiry never gates it locally.
enum ApprovalDecision {
  /// Permit the requested step.
  approve,

  /// Refuse the requested step.
  deny,
}

/// Validated display fields for a payment card approval.
final class PaymentCardDetails {
  /// Creates display values.
  const PaymentCardDetails({
    required this.card,
    required this.targetPackage,
    this.targetHost,
  });

  /// Card label, falling back to the credential name.
  final String card;

  /// Target application package.
  final String targetPackage;

  /// Optional target domain.
  final String? targetHost;

  /// Copies these values with selected replacements.
  PaymentCardDetails copyWith({
    String? card,
    String? targetPackage,
    String? targetHost,
    bool clearTargetHost = false,
  }) => PaymentCardDetails(
    card: card ?? this.card,
    targetPackage: targetPackage ?? this.targetPackage,
    targetHost: clearTargetHost ? null : targetHost ?? this.targetHost,
  );
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// Parses React-compatible payment details; malformed optional fields are absent.
PaymentCardDetails? parsePaymentCardDetails(Object? details) {
  if (details is! Map) return null;
  final card = _string(details['label']) ?? _string(details['credentialName']);
  final app = _string(details['targetPackage']);
  if (card == null || app == null) return null;
  return PaymentCardDetails(
    card: card,
    targetPackage: app,
    targetHost: _string(details['targetHost']),
  );
}

/// Milliseconds until expiry, negative afterwards and zero for invalid dates.
int remainingMs(String expiresAt, int nowMs) =>
    (DateTime.tryParse(expiresAt)?.millisecondsSinceEpoch ?? nowMs) - nowMs;

/// React's countdown format, rounded up to seconds and clamped to zero.
String formatRemaining(num milliseconds) {
  final total = milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return h > 0
      ? '${h}h ${m}m ${s}s'
      : m > 0
      ? '${m}m ${s}s'
      : '${s}s';
}

// Approval details are JSON-shaped; nested maps ignore insertion order.
bool _detailsEqual(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (key) => b.containsKey(key) && _detailsEqual(a[key], b[key]),
        );
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_detailsEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _detailsHash(Object? value) => switch (value) {
  Map() => Object.hashAllUnordered(
    value.entries.map(
      (entry) => Object.hash(entry.key, _detailsHash(entry.value)),
    ),
  ),
  List() => Object.hashAll(value.map(_detailsHash)),
  _ => value.hashCode,
};
