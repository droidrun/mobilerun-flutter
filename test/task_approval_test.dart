// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/src/approval/pending_approval.dart';
import 'package:mobilerun_flutter/src/approval/task_approval_controller.dart';

const approval = PendingApproval(
  approvalId: 'a',
  kind: 'payment_card',
  details: {
    'label': 'Visa 4242',
    'targetPackage': 'com.shop',
    'targetHost': 'shop.com',
  },
  expiresAt: '2026-01-01T00:10:00.000Z',
);

void main() {
  group('React payment details cases', () {
    test('accepts label, package and host', () {
      final card = parsePaymentCardDetails(approval.details)!;
      expect(card.card, 'Visa 4242');
      expect(card.targetPackage, 'com.shop');
      expect(card.targetHost, 'shop.com');
    });
    test('falls back to credentialName and omits host', () {
      final card = parsePaymentCardDetails({
        'credentialName': 'corp',
        'targetPackage': 'com.shop',
      })!;
      expect(card.card, 'corp');
      expect(card.targetHost, isNull);
    });
    test('rejects missing package, missing card and wrong types', () {
      for (final value in [
        {'label': 'x'},
        {'targetPackage': 'com.shop'},
        {'label': 1, 'targetPackage': 'a'},
        null,
        'card',
      ]) {
        expect(parsePaymentCardDetails(value), isNull);
      }
      expect(
        parsePaymentCardDetails({
          'label': 'x',
          'targetPackage': 'a',
          'targetHost': 3,
        })!.targetHost,
        isNull,
      );
      expect(
        parsePaymentCardDetails({
          'label': '',
          'credentialName': 'fallback',
          'targetPackage': 'a',
        })!.card,
        'fallback',
      );
    });
  });
  test('React remainingMs cases', () {
    final base = DateTime.parse(approval.expiresAt).millisecondsSinceEpoch;
    expect(remainingMs(approval.expiresAt, base - 5000), 5000);
    expect(remainingMs(approval.expiresAt, base + 1), -1);
    expect(remainingMs('nope', base), 0);
  });
  test('React formatRemaining cases', () {
    for (final entry in {
      0: '0s',
      59001: '1m 0s',
      3725000: '1h 2m 5s',
      298000: '4m 58s',
      45000: '45s',
      3600000: '1h 0m 0s',
      -5: '0s',
    }.entries) {
      expect(formatRemaining(entry.key), entry.value);
    }
  });

  testWidgets(
    'polls at 3000 ms only after completed fetch; push replaces polling',
    (tester) async {
      var calls = 0;
      final controller = TaskApprovalController(
        taskId: 'task',
        fetchApproval: (_) async {
          calls++;
          return approval;
        },
        decide: (_) async {},
      );
      expect(controller.state.isLoading, isTrue);
      await tester.pump();
      expect(calls, 1);
      expect(controller.state.approval, approval);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(calls, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(calls, 2);
      controller.dispose();
      void Function()? change;
      var unsubscribed = 0;
      final pushed = TaskApprovalController(
        taskId: 'task',
        fetchApproval: (_) async {
          calls++;
          return null;
        },
        decide: (_) async {},
        subscribe: (_, callback) {
          change = callback;
          return () {
            unsubscribed++;
          };
        },
      );
      await tester.pump();
      final before = calls;
      await tester.pump(const Duration(seconds: 9));
      expect(calls, before);
      change!();
      await tester.pump();
      expect(calls, before + 1);
      await pushed.refetch();
      expect(unsubscribed, 0);
      pushed.dispose();
      expect(unsubscribed, 1);
      change!();
      await tester.pump();
      expect(calls, before + 2);
    },
  );

  testWidgets(
    'drops overlapping, changed-task, disabled and disposed results',
    (tester) async {
      final pending = <Completer<PendingApproval?>>[];
      final controller = TaskApprovalController(
        taskId: 'old',
        fetchApproval: (_) {
          final c = Completer<PendingApproval?>();
          pending.add(c);
          return c.future;
        },
        decide: (_) async {},
      );
      final reload = controller.refetch();
      pending[1].complete(approval);
      await reload;
      pending[0].complete(null);
      await tester.pump();
      expect(controller.state.approval, approval);
      controller.update(taskId: 'new');
      controller.update(taskId: 'new', enabled: false);
      pending[2].complete(approval);
      await tester.pump();
      expect(controller.state.approval, isNull);
      expect(controller.state.isLoading, isFalse);
      controller.update(taskId: 'last');
      controller.dispose();
      pending[3].completeError(TimeoutException('late'));
      await tester.pump();
    },
  );

  testWidgets(
    'serializes decisions and refetches after success and 404/409/timeouts',
    (tester) async {
      for (final error in [
        null,
        StateError('404'),
        StateError('409'),
        TimeoutException('integrator cancellation'),
      ]) {
        var fetches = 0;
        var sends = 0;
        final decision = Completer<void>();
        final errors = <Object>[];
        final controller = TaskApprovalController(
          taskId: 'task',
          fetchApproval: (_) async {
            fetches++;
            return fetches == 1 ? approval : null;
          },
          decide: (request) {
            sends++;
            expect(request.taskId, 'task');
            expect(request.approvalId, 'a');
            expect(request.decision, ApprovalDecision.approve);
            return decision.future;
          },
          onError: errors.add,
        );
        await tester.pump();
        final deciding = controller.decide(ApprovalDecision.approve);
        await controller.decide(ApprovalDecision.deny);
        expect(sends, 1);
        expect(controller.state.isDeciding, isTrue);
        if (error == null) {
          decision.complete();
        } else {
          decision.completeError(error);
        }
        await deciding;
        expect(controller.state.isDeciding, isFalse);
        expect(controller.state.approval, isNull);
        expect(fetches, 2);
        expect(controller.state.error, error);
        expect(errors, error == null ? isEmpty : [error]);
        controller.dispose();
      }
    },
  );

  testWidgets('fetch timeout recovers; onError timeout cannot escape', (
    tester,
  ) async {
    var fail = true;
    var errors = 0;
    final controller = TaskApprovalController(
      taskId: 'task',
      fetchApproval: (_) async {
        if (fail) throw TimeoutException('fetch');
        return approval;
      },
      decide: (_) async {},
      onError: (_) async {
        errors++;
        throw TimeoutException('observer');
      },
    );
    await tester.pump();
    expect(controller.state.error, isA<TimeoutException>());
    expect(controller.state.isLoading, isFalse);
    expect(errors, 1);
    fail = false;
    await controller.refetch();
    expect(controller.state.error, isNull);
    expect(controller.state.approval, approval);
    controller.dispose();
  });

  testWidgets('subscribe and unsubscribe timeouts are guarded', (tester) async {
    final controller = TaskApprovalController(
      taskId: 'task',
      fetchApproval: (_) async => approval,
      decide: (_) async {},
      subscribe: (_, _) async => throw TimeoutException('subscribe'),
      onError: (_) => throw TimeoutException('observer'),
    );
    await tester.pump();
    expect(controller.state.error, isA<TimeoutException>());
    controller.dispose();
    final detached = TaskApprovalController(
      taskId: 'task',
      fetchApproval: (_) async => approval,
      decide: (_) async {},
      subscribe: (_, _) => () async {
        throw TimeoutException('unsubscribe');
      },
    );
    await tester.pump();
    detached.update(taskId: '', enabled: false);
    await tester.pump();
    expect(detached.state.error, isA<TimeoutException>());
    detached.dispose();
    await tester.pump();
  });

  testWidgets('stale decisions cannot mutate new task or disposed controller', (
    tester,
  ) async {
    final pending = Completer<void>();
    var fetches = 0;
    final controller = TaskApprovalController(
      taskId: 'old',
      fetchApproval: (_) async {
        fetches++;
        return approval;
      },
      decide: (_) => pending.future,
    );
    await tester.pump();
    final decision = controller.decide(ApprovalDecision.approve);
    controller.update(taskId: 'new');
    await tester.pump();
    pending.completeError(TimeoutException('old decision'));
    await decision;
    expect(controller.state.isDeciding, isFalse);
    expect(controller.state.decision, isNull);
    expect(controller.state.error, isNull);
    expect(fetches, 2);
    controller.dispose();
    final late = Completer<PendingApproval?>();
    var notifications = 0;
    final disposed = TaskApprovalController(
      taskId: 'task',
      fetchApproval: (_) => late.future,
      decide: (_) async {},
    );
    disposed.addListener(() => notifications++);
    disposed.dispose();
    late.complete(approval);
    await tester.pump();
    expect(notifications, 0);
  });
}
