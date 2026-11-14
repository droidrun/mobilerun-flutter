// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'support/fixtures.dart';

void main() {
  final policy = readFixtureObject('reconnect/policy.json');
  final counter = CaseCounter();
  final delayCases = (policy['delay_cases']! as List)
      .cast<Map>()
      .map((c) => c.cast<String, Object?>())
      .toList();

  test('policy constants equal policy.json', () {
    final backoff = (policy['backoff']! as Map).cast<String, Object?>();
    expect(ReconnectPolicy.maxAttempts, policy['max_attempts']);
    expect(
      ReconnectPolicy.wsOpenTimeout.inMilliseconds,
      policy['ws_open_timeout_ms'],
    );
    expect(
      ReconnectPolicy.rtcConfigTimeout.inMilliseconds,
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
          ReconnectPolicy.wsOpenTimeout + ReconnectPolicy.rtcConfigTimeout,
        ),
      );
    },
  );

  group('delay_cases', () {
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
        counter.hit();
      });
    }
  });

  test('every delay case was exercised', () {
    expect(delayCases, isNotEmpty);
    expect(counter.executed, delayCases.length);
  });

  test('default random stays within the jitter band', () {
    for (var i = 0; i < 50; i++) {
      final ms = reconnectDelay(2).inMilliseconds;
      expect(ms, inInclusiveRange(1500, 2500));
    }
  });
}
