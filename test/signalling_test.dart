// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'support/fixtures.dart';

Map<String, Object?> _asObject(Object? value) =>
    (value! as Map).cast<String, Object?>();

void main() {
  final files =
      Directory('conformance/fixtures/signalling')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('client-') || n.startsWith('server-'))
          .toList()
        ..sort();
  final counter = CaseCounter();
  var total = 0;

  for (final file in files) {
    final fixture = readFixtureObject('signalling/$file');
    final direction = fixture['direction']! as String;
    final examples = (fixture['examples']! as List).map(_asObject).toList();
    total += examples.length;
    group(file, () {
      for (final example in examples) {
        final json = _asObject(example['json']);
        test('${example['name']}: parses and re-serializes', () {
          final Map<String, Object?> serialized;
          final String type;
          if (direction == 'client_to_server') {
            final message = ClientMessage.fromJson(json);
            serialized = message.toJson();
            type = message.type;
            expect(jsonDecode(message.encode()), json);
          } else {
            final message = ServerMessage.fromJson(json);
            serialized = message.toJson();
            type = message.type;
            expect(jsonDecode(message.encode()), json);
          }
          expect(serialized, json);
          expect(type, fixture['type']);
          counter.hit();
        });
      }

      test('every required top-level field is serialized', () {
        final required = (fixture['fields']! as List)
            .map(_asObject)
            .where((f) => f['required'] == true)
            .map((f) => f['name']! as String)
            .where((n) => !n.contains('.'));
        for (final example in examples) {
          final json = _asObject(example['json']);
          if (json['rtcConfiguration'] is Map &&
              (json['rtcConfiguration'] as Map).isEmpty) {
            continue;
          }
          expect(json.keys, containsAll(required));
        }
      });
    });
  }

  test('every signalling fixture example was exercised', () {
    expect(files, hasLength(12));
    expect(counter.executed, total);
  });

  group('openUrl', () {
    test('percent-encoded input yields the shown url', () {
      final message = OpenUrlMessage.fromInput(
        input: 'https%3A%2F%2Fexample.test%2Fpath%3Fq%3Da%20b',
        sessionId: 'sess_0123456789abcdef',
      );
      expect(message.url, 'https://example.test/path?q=a b');
    });

    test('undecodable input is sent unchanged', () {
      final message = OpenUrlMessage.fromInput(
        input: 'https://example.test/%zz',
        sessionId: 's',
      );
      expect(message.url, 'https://example.test/%zz');
    });
  });

  group('typed views', () {
    test('rtcConfiguration exposes ice servers', () {
      final message =
          ServerMessage.fromJson(
                _asObject(
                  _asObject(
                    (readFixtureObject(
                              'signalling/server-rtc-configuration.json',
                            )['examples']!
                            as List)
                        .first,
                  )['json'],
                ),
              )
              as RtcConfigurationMessage;
      final servers = message.iceServers!;
      expect(servers, hasLength(2));
      expect(servers[0].urls, ['stun:stun.example.test:3478']);
      expect(servers[1].username, '1700000000:user');
      expect(servers[1].credential, 'cred-example');
    });

    test('refresh without iceServers has none', () {
      const message = RtcConfigurationMessage(rtcConfiguration: {});
      expect(message.iceServers, isNull);
    });
  });

  group('ignore rules', () {
    final sequence = readFixtureObject('signalling/sequence.json');

    test('fixture lists the per-phase ignore rules', () {
      expect(sequence['ignored'], hasLength(3));
    });

    const answer = '{"type":"answer","sdp":"v=0"}';
    const config = '{"type":"rtcConfiguration","rtcConfiguration":{}}';

    test('awaiting: invalid JSON fails startup', () {
      expect(
        () => decodeServerMessage(
          'not json',
          phase: SignallingPhase.awaitingRtcConfiguration,
        ),
        throwsA(isA<SignallingStartupException>()),
      );
    });

    test('awaiting: valid messages of another type are ignored', () {
      expect(
        decodeServerMessage(
          answer,
          phase: SignallingPhase.awaitingRtcConfiguration,
        ),
        isNull,
      );
      expect(
        decodeServerMessage(
          '{"type":"nope"}',
          phase: SignallingPhase.awaitingRtcConfiguration,
        ),
        isNull,
      );
      expect(
        decodeServerMessage(
          '42',
          phase: SignallingPhase.awaitingRtcConfiguration,
        ),
        isNull,
      );
    });

    test('awaiting: rtcConfiguration is the reply', () {
      expect(
        decodeServerMessage(
          config,
          phase: SignallingPhase.awaitingRtcConfiguration,
        ),
        isA<RtcConfigurationMessage>(),
      );
    });

    test('active: invalid JSON is dropped', () {
      expect(
        decodeServerMessage('not json', phase: SignallingPhase.active),
        isNull,
      );
    });

    test('active: unknown type is dropped', () {
      expect(
        decodeServerMessage('{"type":"nope"}', phase: SignallingPhase.active),
        isNull,
      );
    });

    test('active: known messages parse, rtcConfiguration is a refresh', () {
      expect(
        decodeServerMessage(answer, phase: SignallingPhase.active),
        isA<AnswerMessage>(),
      );
      expect(
        decodeServerMessage(config, phase: SignallingPhase.active),
        isA<RtcConfigurationMessage>(),
      );
    });

    test('screenshot replies missing id or payload are ignored', () {
      expect(
        decodeServerMessage(
          '{"type":"screenshot","id":"a"}',
          phase: SignallingPhase.active,
        ),
        isNull,
      );
      expect(
        decodeServerMessage(
          '{"type":"screenshotError","message":"x"}',
          phase: SignallingPhase.active,
        ),
        isNull,
      );
    });
  });

  group('sequence.json', () {
    final sequence = readFixtureObject('signalling/sequence.json');
    final timing = _asObject(sequence['timing']);
    final channels = _asObject(sequence['channels']);

    test('timings', () {
      expect(
        SignallingTiming.wsOpenTimeout.inMilliseconds,
        timing['ws_open_timeout_ms'],
      );
      expect(
        SignallingTiming.rtcConfigTimeout.inMilliseconds,
        timing['rtc_config_timeout_ms'],
      );
      expect(SignallingTiming.requestFrameCount, timing['request_frame_count']);
      expect(
        SignallingTiming.requestFrameInterval.inMilliseconds,
        timing['request_frame_interval_ms'],
      );
      expect(
        SignallingTiming.keepAliveInterval.inMilliseconds,
        timing['keep_alive_interval_ms'],
      );
      expect(
        SignallingTiming.iceRestartGrace.inMilliseconds,
        timing['ice_restart_grace_ms'],
      );
      expect(
        SignallingTiming.screenshotTimeout.inMilliseconds,
        timing['screenshot_timeout_ms'],
      );
    });

    for (final entry in {
      'control': StreamDataChannels.control,
      'hover': StreamDataChannels.hover,
    }.entries) {
      test('${entry.key} data channel', () {
        final fixture = _asObject(channels[entry.key]);
        expect(entry.value.label, fixture['label']);
        expect(entry.value.id, fixture['id']);
        expect(entry.value.ordered, fixture['ordered']);
        expect(entry.value.maxRetransmits, fixture['maxRetransmits']);
      });
    }
  });
}
