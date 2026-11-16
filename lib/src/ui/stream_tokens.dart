// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// React light defaults, converted once from OKLCH to 8-bit sRGB.
@immutable
final class StreamTokens {
  /// Creates values with individually overridable defaults.
  const StreamTokens({
    this.background = const Color(0xFFFFFFFF),
    this.foreground = const Color(0xFF0A0A0A),
    this.card = const Color(0xFFFFFFFF),
    this.cardForeground = const Color(0xFF0A0A0A),
    this.muted = const Color(0xFFF5F5F5),
    this.mutedForeground = const Color(0xFF737373),
    this.border = const Color(0xFFE5E5E5),
    this.ring = const Color(0xFFA1A1A1),
    this.primary = const Color(0xFF171717),
    this.primaryForeground = const Color(0xFFFAFAFA),
    this.accent = const Color(0xFFF5F5F5),
    this.accentForeground = const Color(0xFF171717),
    this.destructive = const Color(0xFFE7000B),
    this.radius = 8,
    this.typography = const TextStyle(fontSize: 14),
  });

  /// background semantic color.
  final Color background;

  /// foreground semantic color.
  final Color foreground;

  /// card semantic color.
  final Color card;

  /// cardForeground semantic color.
  final Color cardForeground;

  /// muted semantic color.
  final Color muted;

  /// mutedForeground semantic color.
  final Color mutedForeground;

  /// border semantic color.
  final Color border;

  /// ring semantic color.
  final Color ring;

  /// primary semantic color.
  final Color primary;

  /// primaryForeground semantic color.
  final Color primaryForeground;

  /// accent semantic color.
  final Color accent;

  /// accentForeground semantic color.
  final Color accentForeground;

  /// destructive semantic color.
  final Color destructive;

  /// Base corner radius: buttons use 0.75 times this value, cards add 4.
  final double radius;

  /// Base typography; components derive their sizes from it.
  final TextStyle typography;

  /// React dark palette; dark mode is opt-in.
  static const dark = StreamTokens(
    background: Color(0xFF0A0A0A),
    foreground: Color(0xFFFAFAFA),
    card: Color(0xFF171717),
    cardForeground: Color(0xFFFAFAFA),
    muted: Color(0xFF262626),
    mutedForeground: Color(0xFFA1A1A1),
    border: Color(0x1AFFFFFF),
    ring: Color(0xFF737373),
    primary: Color(0xFFFAFAFA),
    primaryForeground: Color(0xFF171717),
    accent: Color(0xFF262626),
    accentForeground: Color(0xFFFAFAFA),
    destructive: Color(0xFFFF6467),
  );

  /// Returns a copy with the supplied values replaced.
  StreamTokens copyWith({
    Color? background,
    Color? foreground,
    Color? card,
    Color? cardForeground,
    Color? muted,
    Color? mutedForeground,
    Color? border,
    Color? ring,
    Color? primary,
    Color? primaryForeground,
    Color? accent,
    Color? accentForeground,
    Color? destructive,
    double? radius,
    TextStyle? typography,
  }) => StreamTokens(
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    card: card ?? this.card,
    cardForeground: cardForeground ?? this.cardForeground,
    muted: muted ?? this.muted,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    border: border ?? this.border,
    ring: ring ?? this.ring,
    primary: primary ?? this.primary,
    primaryForeground: primaryForeground ?? this.primaryForeground,
    accent: accent ?? this.accent,
    accentForeground: accentForeground ?? this.accentForeground,
    destructive: destructive ?? this.destructive,
    radius: radius ?? this.radius,
    typography: typography ?? this.typography,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamTokens &&
          other.background == background &&
          other.foreground == foreground &&
          other.card == card &&
          other.cardForeground == cardForeground &&
          other.muted == muted &&
          other.mutedForeground == mutedForeground &&
          other.border == border &&
          other.ring == ring &&
          other.primary == primary &&
          other.primaryForeground == primaryForeground &&
          other.accent == accent &&
          other.accentForeground == accentForeground &&
          other.destructive == destructive &&
          other.radius == radius &&
          other.typography == typography;

  @override
  int get hashCode => Object.hashAll([
    background,
    foreground,
    card,
    cardForeground,
    muted,
    mutedForeground,
    border,
    ring,
    primary,
    primaryForeground,
    accent,
    accentForeground,
    destructive,
    radius,
    typography,
  ]);
}
