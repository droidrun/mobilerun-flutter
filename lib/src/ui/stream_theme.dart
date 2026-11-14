// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'stream_tokens.dart';

/// Scopes SDK tokens independently of the host Material theme.
///
/// Light is the default, matching React. Set [followSystem] to opt into system
/// dark mode, or supply [tokens] explicitly for complete control.
class StreamTheme extends StatelessWidget {
  /// Creates an isolated SDK theme.
  const StreamTheme({
    super.key,
    this.tokens = const StreamTokens(),
    this.darkTokens = StreamTokens.dark,
    this.followSystem = false,
    required this.child,
  });

  /// Light or explicit palette.
  final StreamTokens tokens;

  /// Palette used only for system dark mode with [followSystem].
  final StreamTokens darkTokens;

  /// Explicitly opts into the system brightness.
  final bool followSystem;

  /// The themed subtree.
  final Widget child;

  /// Resolves tokens; unwrapped components always use React's light palette.
  static StreamTokens of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Tokens>()?.tokens ??
      const StreamTokens();

  @override
  Widget build(BuildContext context) {
    final resolved =
        followSystem &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark
        ? darkTokens
        : tokens;
    return _Tokens(
      tokens: resolved,
      child: DefaultTextStyle(
        style: resolved.typography.copyWith(
          inherit: false,
          color: resolved.foreground,
        ),
        child: IconTheme(
          data: IconThemeData(color: resolved.foreground, size: 16),
          child: child,
        ),
      ),
    );
  }
}

class _Tokens extends InheritedWidget {
  const _Tokens({required this.tokens, required super.child});
  final StreamTokens tokens;

  @override
  bool updateShouldNotify(_Tokens oldWidget) => oldWidget.tokens != tokens;
}
