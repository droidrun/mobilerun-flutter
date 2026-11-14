// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

/// Offline gallery for labels, themes and backend-driven approvals.
void main() => runApp(const MaterialApp(home: UiGallery()));

/// A self-contained fake backend demo; no API key or device is required.
class UiGallery extends StatefulWidget {
  const UiGallery({super.key});
  @override
  State<UiGallery> createState() => _UiGalleryState();
}

class _UiGalleryState extends State<UiGallery> {
  late TaskApprovalController _approval;
  PendingApproval? _pending;
  var _fetches = 0;
  var _scenario = 'light';
  var _last = '';

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _pending = PendingApproval(
      approvalId: 'demo-approval',
      kind: _scenario == 'unknown' ? 'future' : 'payment_card',
      details: const {
        'label': 'Visa 4242',
        'targetPackage': 'com.shop',
        'targetHost': 'shop.example',
      },
      expiresAt: DateTime.now()
          .toUtc()
          .add(Duration(seconds: _scenario == 'expired' ? -1 : 298))
          .toIso8601String(),
    );
    _fetches = 0;
    _last = '';
    _approval = TaskApprovalController(
      taskId: 'demo-task',
      fetchApproval: (_) async {
        _fetches++;
        return _pending;
      },
      decide: (request) async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (_scenario == 'error') {
          throw StateError('The approval changed. Please try again.');
        }
        _pending = null;
        if (mounted) setState(() => _last = request.decision.name);
      },
    );
  }

  void _select(String scenario) {
    _approval.dispose();
    setState(() {
      _scenario = scenario;
      _reset();
    });
  }

  @override
  void dispose() {
    _approval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _scenario == 'dark'
        ? StreamTokens.dark
        : _scenario == 'custom'
        ? const StreamTokens().copyWith(
            primary: const Color(0xff005b50),
            background: const Color(0xfff2faf5),
            card: const Color(0xfff2faf5),
            radius: 12,
          )
        : const StreamTokens();
    final labels = _scenario == 'custom'
        ? const StreamLabels(
            approve: 'Freigeben',
            deny: 'Ablehnen',
            paymentCardTitle: 'Zahlung freigeben',
            timeLeft: 'Noch {time}',
            card: 'Karte',
            app: 'App',
            domain: 'Domain',
          )
        : const StreamLabels();
    return StreamTheme(
      tokens: tokens,
      child: Scaffold(
        backgroundColor: tokens.background,
        appBar: AppBar(title: const Text('UI gallery')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mode in [
                      'light',
                      'dark',
                      'custom',
                      'unknown',
                      'error',
                      'expired',
                    ])
                      ActionChip(
                        label: Text(mode),
                        onPressed: () => _select(mode),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: _approval,
                  builder: (context, _) {
                    final state = _approval.state;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TaskApprovalCard(
                          approval: state.approval,
                          onDecide: (decision) =>
                              unawaited(_approval.decide(decision)),
                          isPending: state.isDeciding,
                          decision: state.decision,
                          error: state.error,
                          labels: labels,
                        ),
                        if (state.approval == null && !state.isLoading)
                          Text(
                            'Decision: $_last; backend fetches: $_fetches',
                            style: tokens.typography.copyWith(
                              color: tokens.foreground,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: StreamStatusPill(label: 'connecting'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
