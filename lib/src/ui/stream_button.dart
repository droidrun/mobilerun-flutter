// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal shared implementation, intentionally excluded from the public barrel.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

import 'stream_theme.dart';

/// Internal button styling shared by the default chrome and approval card.
class StreamButton extends StatelessWidget {
  const StreamButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outline = false,
    this.ghost = false,
    this.pending = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outline;
  final bool ghost;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final t = StreamTheme.of(context);
    final foreground = outline || ghost ? t.foreground : t.primaryForeground;
    return Opacity(
      opacity: onPressed == null ? .5 : 1,
      child: TextButton(
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(40, 36)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: ghost ? 8 : 16),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                (outline || ghost) &&
                    states.any(
                      {WidgetState.hovered, WidgetState.focused}.contains,
                    )
                ? t.accentForeground
                : foreground,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                (outline || ghost) &&
                    states.any(
                      {WidgetState.hovered, WidgetState.focused}.contains,
                    )
                ? t.accent
                : ghost
                ? Colors.transparent
                : outline
                ? t.background
                : t.primary,
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? t.ring.withValues(alpha: .3)
                : Colors.transparent,
          ),
          textStyle: WidgetStatePropertyAll(
            t.typography.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ghost ? 0 : t.radius),
              side: outline ? BorderSide(color: t.border) : BorderSide.none,
            ),
          ),
        ),
        child: IconTheme(
          data: IconThemeData(size: 16, color: foreground),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pending)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else if (icon != null)
                Icon(icon),
              if (!ghost) ...[
                if (pending || icon != null) const SizedBox(width: 8),
                Flexible(child: Text(label)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
