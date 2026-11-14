// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../approval/pending_approval.dart';
import 'stream_button.dart';
import 'task_approval_labels.dart';
import 'stream_theme.dart';

/// State passed to an approval actions slot.
final class ApprovalActionsState {
  /// Creates the actions state.
  const ApprovalActionsState({
    this.isPending = false,
    this.decision,
    this.labels = const TaskApprovalLabels(),
    required this.onDecide,
  });

  /// Whether a backend decision is in flight.
  final bool isPending;

  /// In-flight or last decision.
  final ApprovalDecision? decision;

  /// Overridable labels.
  final TaskApprovalLabels labels;

  /// Forwards a decision to the integrator.
  final ValueChanged<ApprovalDecision> onDecide;
}

/// Builds a replacement for the approval action buttons.
typedef ApprovalActionsBuilder =
    Widget Function(BuildContext context, ApprovalActionsState state);

/// Default approve and deny actions, also usable inside a custom slot.
Widget defaultApprovalActions(
  BuildContext context,
  ApprovalActionsState state,
) => Row(
  children: [
    Expanded(
      child: StreamButton(
        label: state.labels.approve,
        icon: Icons.check,
        pending: state.isPending && state.decision == ApprovalDecision.approve,
        onPressed: state.isPending
            ? null
            : () => state.onDecide(ApprovalDecision.approve),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: StreamButton(
        label: state.labels.deny,
        icon: Icons.close,
        outline: true,
        pending: state.isPending && state.decision == ApprovalDecision.deny,
        onPressed: state.isPending
            ? null
            : () => state.onDecide(ApprovalDecision.deny),
      ),
    ),
  ],
);

/// White-label approval card. Expiry is display-only; the backend decides.
///
/// The optional device remains mounted across mobile tabs and the 768 pixel
/// breakpoint. Only the countdown's small subtree rebuilds each second.
class TaskApprovalCard extends StatefulWidget {
  /// Creates a card; null approvals render nothing.
  const TaskApprovalCard({
    super.key,
    this.approval,
    required this.onDecide,
    this.isPending = false,
    this.decision,
    this.error,
    this.device,
    this.labels = const TaskApprovalLabels(),
    this.actionsBuilder = defaultApprovalActions,
  });

  /// Backend pending approval.
  final PendingApproval? approval;

  /// Forwards a decision; never disabled by local expiry.
  final ValueChanged<ApprovalDecision> onDecide;

  /// Disables both actions while the decision is in flight.
  final bool isPending;

  /// Action showing the progress indicator.
  final ApprovalDecision? decision;

  /// Backend or integrator error, announced assertively.
  final String? error;

  /// Optional live device widget, kept mounted when hidden.
  final Widget? device;

  /// Overrides every built-in string.
  final TaskApprovalLabels labels;

  /// Replaces the two decision buttons.
  final ApprovalActionsBuilder actionsBuilder;

  @override
  State<TaskApprovalCard> createState() => _TaskApprovalCardState();
}

class _TaskApprovalCardState extends State<TaskApprovalCard> {
  bool _showDevice = false;
  int _announcementEpoch = 0;

  @override
  void initState() {
    super.initState();
    _announce();
  }

  @override
  void didUpdateWidget(TaskApprovalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.approval?.approvalId != oldWidget.approval?.approvalId) {
      _showDevice = false;
    }
    if (widget.error != oldWidget.error ||
        (widget.approval == null) != (oldWidget.approval == null)) {
      _announce();
    }
  }

  void _announce() {
    final epoch = ++_announcementEpoch;
    if (widget.error == null || widget.approval == null) return;
    final text = widget.error!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _announcementEpoch || widget.approval == null) {
        return;
      }
      // Keep the package's Flutter 3.32 minimum; sendAnnouncement is newer.
      // ignore: deprecated_member_use
      SemanticsService.announce(
        text,
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      );
    });
  }

  Widget _actions(BuildContext context) {
    final t = StreamTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.error != null) ...[
          Text(
            widget.error!,
            style: t.typography.copyWith(color: t.destructive),
          ),
          const SizedBox(height: 16),
        ],
        widget.actionsBuilder(
          context,
          ApprovalActionsState(
            isPending: widget.isPending,
            decision: widget.decision,
            labels: widget.labels,
            onDecide: widget.onDecide,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final approval = widget.approval;
    if (approval == null) return const SizedBox.shrink();
    final t = StreamTheme.of(context);
    final labels = widget.labels;
    final card = approval.kind == 'payment_card'
        ? parsePaymentCardDetails(approval.details)
        : null;
    final title = card == null ? labels.waiting : labels.paymentCardTitle;
    return Semantics(
      container: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.card,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(t.radius * 2),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 768;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle(
                style: t.typography.copyWith(color: t.cardForeground),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: t.typography.copyWith(
                        color: t.cardForeground,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Countdown(expiresAt: approval.expiresAt, labels: labels),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final hasDevice = widget.device != null;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Offstage(
                              offstage: wide || !hasDevice,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Semantics(
                                  label: labels.viewSwitch,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Semantics(
                                          selected: !_showDevice,
                                          child: StreamButton(
                                            label: labels.details,
                                            icon: Icons.list_alt,
                                            outline: _showDevice,
                                            onPressed: () => setState(
                                              () => _showDevice = false,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Semantics(
                                          selected: _showDevice,
                                          child: StreamButton(
                                            label: labels.device,
                                            icon: Icons.smartphone,
                                            outline: !_showDevice,
                                            onPressed: () => setState(
                                              () => _showDevice = true,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Flex(
                              direction: wide ? Axis.horizontal : Axis.vertical,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  flex: wide ? 1 : 0,
                                  fit: FlexFit.loose,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Offstage(
                                        offstage:
                                            !wide && hasDevice && _showDevice,
                                        child: card == null
                                            ? const SizedBox.shrink()
                                            : DecoratedBox(
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: t.border,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        t.radius + 2,
                                                      ),
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    _Fact(
                                                      icon: Icons.credit_card,
                                                      label: labels.card,
                                                      value: card.card,
                                                    ),
                                                    Divider(
                                                      height: 1,
                                                      color: t.border,
                                                    ),
                                                    _Fact(
                                                      icon: Icons.apps,
                                                      label: labels.app,
                                                      value: card.targetPackage,
                                                    ),
                                                    if (card.targetHost !=
                                                        null) ...[
                                                      Divider(
                                                        height: 1,
                                                        color: t.border,
                                                      ),
                                                      _Fact(
                                                        icon: Icons.public,
                                                        label: labels.domain,
                                                        value: card.targetHost!,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                      ),

                                      if (wide) ...[
                                        const SizedBox(height: 16),
                                        _actions(context),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(width: wide && hasDevice ? 24 : 0),
                                // Keep the same keyed slot across tabs and Flex directions.
                                Offstage(
                                  key: const ValueKey('approval-device'),
                                  offstage:
                                      !hasDevice || (!wide && !_showDevice),
                                  child: SizedBox(
                                    width: wide
                                        ? 256
                                        : constraints.maxWidth - 32,
                                    height: wide ? 400 : 320,
                                    child: widget.device,
                                  ),
                                ),
                              ],
                            ),
                            if (!wide) ...[
                              const SizedBox(height: 16),
                              _actions(context),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = StreamTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: t.muted,
              borderRadius: BorderRadius.circular(t.radius),
            ),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 16, color: t.mutedForeground),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: t.typography.copyWith(
                    fontSize: 12,
                    color: t.mutedForeground,
                  ),
                ),
                Text(
                  value,
                  style: t.typography.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: t.cardForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Countdown extends StatefulWidget {
  const _Countdown({required this.expiresAt, required this.labels});
  final String expiresAt;
  final TaskApprovalLabels labels;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(_Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) _tick();
  }

  void _tick() {
    _timer?.cancel();
    _remaining = remainingMs(
      widget.expiresAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (_remaining > 0) {
      _timer = Timer(
        Duration(milliseconds: _remaining < 1000 ? _remaining : 1000),
        () {
          if (mounted) setState(_tick);
        },
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = StreamTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.muted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 14, color: t.mutedForeground),
            const SizedBox(width: 6),
            Text(
              _remaining > 0
                  ? widget.labels.timeLeft.replaceAll(
                      '{time}',
                      formatRemaining(_remaining),
                    )
                  : widget.labels.expired,
              style: t.typography.copyWith(
                fontSize: 12,
                color: t.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
