// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import 'stream_theme.dart';

/// A small spinner and label; its parent controls overlay positioning.
class StreamStatusPill extends StatelessWidget {
  /// Creates a pill with an integrator-overridable label.
  const StreamStatusPill({super.key, required this.label});

  /// Connection or device state label.
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = StreamTheme.of(context);
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.card.withValues(alpha: .8),
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.mutedForeground,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    style: t.typography.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: t.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
