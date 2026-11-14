// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import '../protocol/js_math.dart';

/// Constants of the reconnect policy, shared by every Mobilerun stream SDK.
abstract final class ReconnectPolicy {
  ReconnectPolicy._();

  /// Consecutive failed attempts after which the stream is declared
  /// unavailable.
  static const int maxAttempts = 6;

  /// How long the signalling WebSocket may take to open.
  static const Duration wsOpenTimeout = Duration(seconds: 15);

  /// How long the `rtcConfiguration` reply may take after the socket opened.
  static const Duration rtcConfigTimeout = Duration(seconds: 15);

  /// Watchdog for a whole connect attempt. It must exceed [wsOpenTimeout] plus
  /// [rtcConfigTimeout], or it would preempt handshakes the connection layer
  /// still considers on budget.
  static const Duration connectTimeout = Duration(seconds: 45);

  /// How long a connection must hold to refill the retry budget.
  static const Duration stability = Duration(seconds: 30);

  /// Backoff before the first retry.
  static const Duration baseDelay = Duration(seconds: 1);

  /// Upper bound of the backoff before jitter.
  static const Duration maxDelay = Duration(seconds: 30);
}

/// The wait before reconnect attempt number [attempt] (1-based).
///
/// Exponential from [ReconnectPolicy.baseDelay], capped at
/// [ReconnectPolicy.maxDelay], then scaled by `0.75 + random * 0.5` (±25 %)
/// and rounded half toward positive infinity. [random] returns a value in
/// [0, 1) and defaults to a `dart:math` generator.
Duration reconnectDelay(int attempt, {double Function()? random}) {
  final nextDouble = random ?? math.Random().nextDouble;
  final baseMs = math.min(
    ReconnectPolicy.baseDelay.inMilliseconds *
        math.pow(2.0, math.max(1, attempt) - 1),
    ReconnectPolicy.maxDelay.inMilliseconds,
  );
  return Duration(milliseconds: jsRound(baseMs * (0.75 + nextDouble() * 0.5)));
}
