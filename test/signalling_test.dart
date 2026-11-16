// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:mobilerun_flutter/src/protocol/stream_timing.dart';
import 'package:mobilerun_flutter/src/protocol/stream_spec.dart';
import 'package:mobilerun_flutter/src/protocol/signalling.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

String _string(Map<String, Object?> json, String key) => json[key]! as String;

/// Builds each client message from the fixture example, keyed by wire type.
final Map<String, ClientMessage Function(Map<String, Object?>)>
_clientBuilders = {
  'requestRtcConfiguration': (j) =>
      RequestRtcConfigurationMessage(sessionId: _string(j, 'sessionId')),
  'offer': (j) =>
      OfferMessage(sdp: _string(j, 'sdp'), sessionId: _string(j, 'sessionId')),
  'candidate': (j) => ClientCandidateMessage(
    candidate: _string(j, 'candidate'),
    sdpMid: j['sdpMid'] as String?,
    sdpMLineIndex: j['sdpMLineIndex'] as int?,
    sessionId: _string(j, 'sessionId'),
  ),
  'keepAlive': (j) => KeepAliveMessage(sessionId: _string(j, 'sessionId')),
  'requestFrame': (j) =>
      RequestFrameMessage(sessionId: _string(j, 'sessionId')),
  'openUrl': (j) => OpenUrlMessage.fromInput(
    input: _string(j, 'url'),
    sessionId: _string(j, 'sessionId'),
  ),
  'screenshot': (j) => ScreenshotRequestMessage(id: _string(j, 'id')),
};

/// Asserts the fields of the parsed server message against the example JSON.
final Map<String, void Function(ServerMessage, Map<String, Object?>)>
_serverChecks = {
  'answer': (m, j) {
    expect((m as AnswerMessage).sdp, j['sdp']);
  },
  'candidate': (m, j) {
    final message = m as ServerCandidateMessage;
    expect(message.candidate, j['candidate']);
    expect(message.sdpMid, j['sdpMid']);
    expect(message.sdpMLineIndex, j['sdpMLineIndex']);
  },
  'rtcConfiguration': (m, j) {
    expect(
      (m as RtcConfigurationMessage).rtcConfiguration,
      j['rtcConfiguration'],
    );
  },
  'screenshot': (m, j) {
    final message = m as ScreenshotMessage;
    expect(message.id, j['id']);
    expect(message.dataUri, j['dataUri']);
  },
  'screenshotError': (m, j) {
    final message = m as ScreenshotErrorMessage;
    expect(message.id, j['id']);
    expect(message.message, j['message']);
  },
};

void main() {
  final files =
      Directory('conformance/fixtures/signalling')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('client-') || n.startsWith('server-'))
          .toList()
        ..sort();

  test('has signalling fixture files', () => expect(files, isNotEmpty));

  for (final file in files) {
    final fixture = readFixtureObject('signalling/$file');
    final type = fixture['type']! as String;
    final isClient = fixture['direction'] == 'client_to_server';
    group(file, () {
      for (final example in readObjects('signalling/$file', 'examples')) {
        final json = asObject(example['json']);
        test(example['name']! as String, () {
          if (isClient) {
            final message = _clientBuilders[type]!(json);
            expect(message.type, type);
            expect(message.toJson(), json);
            expect(jsonDecode(message.encode()), json);
          } else {
            final message = ServerMessage.fromJson(json);
            expect(message.type, type);
            _serverChecks[type]!(message, json);
          }
        });
      }
    });
  }

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
      for (final text in [answer, '{"type":"nope"}', '42']) {
        expect(
          decodeServerMessage(
            text,
            phase: SignallingPhase.awaitingRtcConfiguration,
          ),
          isNull,
        );
      }
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
    final timing = asObject(sequence['timing']);
    final channels = asObject(sequence['channels']);

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
        final fixture = asObject(channels[entry.key]);
        expect(entry.value.label, fixture['label']);
        expect(entry.value.id, fixture['id']);
        expect(entry.value.negotiated, fixture['negotiated']);
        expect(entry.value.ordered, fixture['ordered']);
        expect(entry.value.maxRetransmits, fixture['maxRetransmits']);
      });
    }
  });
}
