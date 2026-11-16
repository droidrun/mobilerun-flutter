// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:mobilerun_flutter/src/core/reconnect_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_scheduler.dart';
import 'support/fixtures.dart';

void main() {
  final fixture = readFixtureObject('reconnect/scenarios.json');
  final scenarios = readObjects('reconnect/scenarios.json', 'scenarios');

  test('event vocabulary is the one the replay maps', () {
    expect(fixture['events'], [
      'attempt_mounted',
      'connected',
      'disconnected',
      'failure',
      'wake',
      'retry',
      'disable',
      'dispose',
    ]);
  });

  for (final scenario in scenarios) {
    test(scenario['name']! as String, () {
      final scheduler = FakeScheduler();
      final random = (scenario['random']! as num).toDouble();
      var healCalls = 0;
      var remountCalls = 0;
      final controller = ReconnectController(
        scheduler: scheduler,
        random: () => random,
        onHeal: () => healCalls += 1,
        onRemount: () => remountCalls += 1,
        onSnapshot: (_) {},
      );

      final steps = (scenario['steps']! as List).map(asObject).toList();
      final expectations = (scenario['expect']! as List).map(asObject).toList();

      void apply(String event) {
        switch (event) {
          case 'attempt_mounted':
            controller.attemptMounted();
          case 'connected':
            controller.handleConnected();
          case 'disconnected':
            controller.handleDisconnected();
          case 'failure':
            controller.handleFailure();
          case 'wake':
            controller.handleWake();
          case 'retry':
            controller.retry();
          case 'disable':
            controller.setDisabled();
          case 'dispose':
            controller.dispose();
          default:
            fail('unknown event $event');
        }
      }

      void check(Map<String, Object?> expected, int index) {
        scheduler.advanceTo(expected['at_ms']! as int);
        final where = 'expect #$index at ${expected['at_ms']} ms';
        final snapshot = controller.snapshot;
        expect(
          snapshot.status.name,
          expected['status'],
          reason: '$where status',
        );
        expect(snapshot.attempt, expected['attempt'], reason: '$where attempt');
        expect(healCalls, expected['heal_calls'], reason: '$where heal_calls');
        expect(
          remountCalls,
          expected['remount_calls'],
          reason: '$where remount_calls',
        );
        if (expected.containsKey('defer_target_change')) {
          expect(
            controller.shouldDeferTargetChange(),
            expected['defer_target_change'],
            reason: '$where defer_target_change',
          );
        }
        if (expected.containsKey('pending_timers')) {
          expect(
            scheduler.pendingTimers,
            expected['pending_timers'],
            reason: '$where pending_timers',
          );
        }
      }

      var i = 0;
      var evaluated = 0;
      while (true) {
        final due = expectations.where((e) => e['after_steps'] == i).toList()
          ..sort((a, b) => (a['at_ms']! as int).compareTo(b['at_ms']! as int));
        for (final expected in due) {
          check(expected, evaluated++);
        }
        if (i >= steps.length) break;
        scheduler.advanceTo(steps[i]['at_ms']! as int);
        apply(steps[i]['event']! as String);
        i += 1;
      }
      expect(
        evaluated,
        expectations.length,
        reason: 'all expectations replayed',
      );
    });
  }

  test('has fixture scenarios', () => expect(scenarios, isNotEmpty));

  test('snapshot callback reports status changes', () {
    final scheduler = FakeScheduler();
    final seen = <ReconnectSnapshot>[];
    ReconnectController(
        scheduler: scheduler,
        random: () => 0.5,
        onHeal: () {},
        onRemount: () {},
        onSnapshot: seen.add,
      )
      ..attemptMounted()
      ..handleConnected();
    expect(seen, [
      const ReconnectSnapshot(status: ReconnectStatus.connected, attempt: 0),
    ]);
  });

  test(
    'attemptMounted after dispose leaves pendingTimers at 0 and emits nothing',
    () {
      final scheduler = FakeScheduler();
      final seen = <ReconnectSnapshot>[];
      final controller = ReconnectController(
        scheduler: scheduler,
        random: () => 0.5,
        onHeal: () {},
        onRemount: () {},
        onSnapshot: seen.add,
      )..dispose();
      controller
        ..attemptMounted()
        ..setDisabled()
        ..handleConnected()
        ..handleFailure()
        ..handleWake()
        ..retry();
      expect(scheduler.pendingTimers, 0);
      expect(seen, isEmpty);
    },
  );
}
