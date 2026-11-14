// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// `Math.round` of JavaScript: halves round toward positive infinity
/// (`2.5 -> 3`, `-0.5 -> 0`, `-1.5 -> -1`). Dart's [num.round] rounds halves
/// away from zero, which would encode `-0.5` and `-1.5` differently.
///
/// Throws an [ArgumentError] when [value] is not finite.
int jsRound(num value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'must be finite');
  }
  final floor = value.floor();
  return value - floor >= 0.5 ? floor + 1 : floor;
}
