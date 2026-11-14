// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/reconnect_policy.dart'
    show reconnectDelay;

import 'support/fixtures.dart';

void main() {
  final policy = readFixtureObject('reconnect/policy.json');
  final delayCases = readObjects('reconnect/policy.json', 'delay_cases');

  test('policy constants equal policy.json', () {
    final backoff = asObject(policy['backoff']);
    expect(ReconnectPolicy.maxAttempts, policy['max_attempts']);
    expect(
      SignallingTiming.wsOpenTimeout.inMilliseconds,
      policy['ws_open_timeout_ms'],
    );
    expect(
      SignallingTiming.rtcConfigTimeout.inMilliseconds,
      policy['rtc_config_timeout_ms'],
    );
    expect(
      ReconnectPolicy.connectTimeout.inMilliseconds,
      policy['connect_timeout_ms'],
    );
    expect(ReconnectPolicy.stability.inMilliseconds, policy['stability_ms']);
    expect(ReconnectPolicy.baseDelay.inMilliseconds, backoff['base_delay_ms']);
    expect(ReconnectPolicy.maxDelay.inMilliseconds, backoff['max_delay_ms']);
  });

  test(
    'invariant: connect_timeout_ms > ws_open_timeout_ms + rtc_config_timeout_ms',
    () {
      expect(
        (policy['invariants']! as List).single,
        'connect_timeout_ms > ws_open_timeout_ms + rtc_config_timeout_ms',
      );
      expect(
        ReconnectPolicy.connectTimeout,
        greaterThan(
          SignallingTiming.wsOpenTimeout + SignallingTiming.rtcConfigTimeout,
        ),
      );
    },
  );

  group('delay_cases', () {
    test('has fixture cases', () => expect(delayCases, isNotEmpty));
    for (final c in delayCases) {
      test('attempt ${c['attempt']} random ${c['random']}', () {
        final random = (c['random']! as num).toDouble();
        expect(
          reconnectDelay(
            c['attempt']! as int,
            random: () => random,
          ).inMilliseconds,
          c['delay_ms'],
        );
      });
    }
  });

  test('default random stays within the jitter band', () {
    for (var i = 0; i < 50; i++) {
      expect(reconnectDelay(2).inMilliseconds, inInclusiveRange(1500, 2500));
    }
  });
}
