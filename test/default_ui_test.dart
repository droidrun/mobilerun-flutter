// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

const approval = PendingApproval(
  approvalId: 'a',
  kind: 'payment_card',
  details: {
    'label': 'Visa 4242',
    'targetPackage': 'com.shop',
    'targetHost': 'shop.com',
  },
  expiresAt: '2000-01-01T00:00:00Z',
);

Widget host(
  Widget child, {
  StreamTokens tokens = const StreamTokens(),
  bool followSystem = false,
}) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: StreamTheme(
        tokens: tokens,
        followSystem: followSystem,
        child: child,
      ),
    ),
  ),
);

class MountProbe extends StatefulWidget {
  const MountProbe({super.key, required this.onMount});
  final VoidCallback onMount;
  @override
  State<MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.black,
    child: Center(child: Text('device slot')),
  );
}

void main() {
  test('React light/dark sRGB defaults, labels and copyWith', () {
    const light = StreamTokens();
    const dark = StreamTokens.dark;
    expect(
      [
        light.background,
        light.foreground,
        light.card,
        light.cardForeground,
        light.muted,
        light.mutedForeground,
        light.border,
        light.ring,
        light.primary,
        light.primaryForeground,
        light.accent,
        light.accentForeground,
        light.destructive,
      ],
      const [
        Color(0xffffffff),
        Color(0xff0a0a0a),
        Color(0xffffffff),
        Color(0xff0a0a0a),
        Color(0xfff5f5f5),
        Color(0xff737373),
        Color(0xffe5e5e5),
        Color(0xffa1a1a1),
        Color(0xff171717),
        Color(0xfffafafa),
        Color(0xfff5f5f5),
        Color(0xff171717),
        Color(0xffe7000b),
      ],
    );
    expect(
      [
        dark.background,
        dark.foreground,
        dark.card,
        dark.cardForeground,
        dark.muted,
        dark.mutedForeground,
        dark.border,
        dark.ring,
        dark.primary,
        dark.primaryForeground,
        dark.accent,
        dark.accentForeground,
        dark.destructive,
      ],
      const [
        Color(0xff0a0a0a),
        Color(0xfffafafa),
        Color(0xff171717),
        Color(0xfffafafa),
        Color(0xff262626),
        Color(0xffa1a1a1),
        Color(0x1affffff),
        Color(0xff737373),
        Color(0xfffafafa),
        Color(0xff171717),
        Color(0xff262626),
        Color(0xfffafafa),
        Color(0xffff6467),
      ],
    );
    expect(light.radius, 6);
    expect(light.copyWith(primary: Colors.blue).foreground, light.foreground);
    final labels = const StreamLabels().copyWith(approve: 'Freigeben');
    expect(labels.approve, 'Freigeben');
    expect(labels.deny, 'Deny');
    const defaults = StreamLabels();
    expect(
      [
        defaults.paymentCardTitle,
        defaults.waiting,
        defaults.card,
        defaults.app,
        defaults.domain,
        defaults.timeLeft,
        defaults.expired,
        defaults.approve,
        defaults.deny,
        defaults.viewSwitch,
        defaults.details,
        defaults.device,
      ],
      [
        'Approve payment',
        'Waiting for approval',
        'Card',
        'App',
        'Domain',
        '{time} left',
        'Approval expired',
        'Approve',
        'Deny',
        'Approval view',
        'Details',
        'Device',
      ],
    );
    expect(
      approval.copyWith(deviceId: 'd').copyWith(clearDeviceId: true).deviceId,
      isNull,
    );
    expect(
      const TaskApprovalState().copyWith(isLoading: true).isLoading,
      isTrue,
    );
  });

  testWidgets(
    'light default ignores host dark; explicit follow-system opts in',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      late StreamTokens found;
      final child = Builder(
        builder: (context) {
          found = StreamTheme.of(context);
          return const SizedBox();
        },
      );
      await tester.pumpWidget(host(child));
      expect(found.background, const Color(0xffffffff));
      await tester.pumpWidget(host(child, followSystem: true));
      expect(found.background, StreamTokens.dark.background);
      await tester.pumpWidget(
        host(
          child,
          tokens: const StreamTokens().copyWith(background: Colors.purple),
        ),
      );
      expect(found.background, Colors.purple);
    },
  );

  testWidgets(
    'expired countdown is display-only, null and unknown kinds, labels and custom actions',
    (tester) async {
      final decisions = <ApprovalDecision>[];
      await tester.pumpWidget(
        host(TaskApprovalCard(approval: approval, onDecide: decisions.add)),
      );
      expect(find.text('Visa 4242'), findsOneWidget);
      expect(find.text('shop.com'), findsOneWidget);
      expect(find.text('Approval expired'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.tap(find.text('Deny'));
      expect(decisions, [ApprovalDecision.approve, ApprovalDecision.deny]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        host(
          TaskApprovalCard(
            approval: approval.copyWith(kind: 'future'),
            onDecide: decisions.add,
            labels: const StreamLabels(approve: 'Allow', waiting: 'Confirm'),
          ),
        ),
      );
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Visa 4242'), findsNothing);
      expect(find.text('Allow'), findsOneWidget);
      await tester.pumpWidget(
        host(
          TaskApprovalCard(
            approval: approval,
            onDecide: decisions.add,
            actionsBuilder: (_, state) => TextButton(
              onPressed: () => state.onDecide(ApprovalDecision.deny),
              child: const Text('custom action'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('custom action'));
      expect(decisions.last, ApprovalDecision.deny);
      await tester.pumpWidget(host(TaskApprovalCard(onDecide: decisions.add)));
      expect(find.text('Approve payment'), findsNothing);
    },
  );

  testWidgets('pending dims whole buttons and prevents duplicate decisions', (
    tester,
  ) async {
    var sends = 0;
    await tester.pumpWidget(
      host(
        TaskApprovalCard(
          approval: approval,
          onDecide: (_) => sends++,
          isPending: true,
          decision: ApprovalDecision.approve,
        ),
      ),
    );
    await tester.tap(find.text('Approve'));
    await tester.tap(find.text('Deny'));
    expect(sends, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((w) => w.opacity == .5),
      hasLength(2),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('device preserves state across tabs, breakpoint and rotation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var mounts = 0;
    final device = MountProbe(onMount: () => mounts++);
    final card = TaskApprovalCard(
      approval: approval,
      onDecide: (_) {},
      device: device,
    );
    await tester.pumpWidget(host(card));
    expect(mounts, 1);
    expect(find.text('device slot'), findsNothing);
    await tester.tap(find.text('Device'));
    await tester.pump();
    expect(find.text('device slot'), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(find.text('device slot'), findsNothing);
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pump();
    expect(find.text('device slot'), findsOneWidget);
    expect(mounts, 1);
    tester.view.physicalSize = const Size(767, 900);
    await tester.pump();
    expect(find.text('device slot'), findsNothing);
    expect(mounts, 1);
    tester.view.physicalSize = const Size(768, 900);
    await tester.pump();
    expect(find.text('device slot'), findsOneWidget);
    expect(mounts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('countdown ticks alone and stops at expiry', (tester) async {
    var actionBuilds = 0;
    final soon = approval.copyWith(
      expiresAt: DateTime.now()
          .toUtc()
          .add(const Duration(milliseconds: 100))
          .toIso8601String(),
    );
    await tester.pumpWidget(
      host(
        TaskApprovalCard(
          approval: soon,
          onDecide: (_) {},
          actionsBuilder: (context, state) {
            actionBuilds++;
            return defaultApprovalActions(context, state);
          },
        ),
      ),
    );
    expect(find.text('1s left'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Approval expired'), findsOneWidget);
    expect(actionBuilds, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(actionBuilds, 1);
    // A disposed future timer would fail this widget test's pending-timer check.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('approval errors announce assertively', (tester) async {
    final announcements = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        announcements.add(message);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );
    await tester.pumpWidget(
      host(
        TaskApprovalCard(
          approval: approval,
          onDecide: (_) {},
          error: 'Rejected',
        ),
      ),
    );
    expect(find.text('Rejected'), findsOneWidget);
    expect(
      announcements.whereType<Map>().any(
        (a) =>
            a['type'] == 'announce' && (a['data'] as Map)['assertiveness'] == 1,
      ),
      isTrue,
    );
  });
}
