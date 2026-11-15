// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/stream_transports.dart';
import 'package:mobilerun_flutter/src/webrtc/stream_stats_parser.dart';

import 'support/fake_transports.dart';
import 'support/harness.dart';

// W3C-shaped getStats snapshots: a transport selects a pair; the inbound
// stream links to its codec. Totals are seconds; counter differences matter.
const _recorded = '''[
 {"id":"video","type":"inbound-rtp","kind":"video","transportId":"transport","codecId":"codec","frameWidth":1080,"frameHeight":2400,"framesDecoded":100,"bytesReceived":100000,"jitterBufferDelay":1.2,"jitterBufferEmittedCount":100,"totalDecodeTime":0.3,"packetsLost":2,"framesDropped":3,"freezeCount":1},
 {"id":"codec","type":"codec","mimeType":"video/H264"},
 {"id":"transport","type":"transport","selectedCandidatePairId":"pair"},
 {"id":"pair","type":"candidate-pair","currentRoundTripTime":0.04,"localCandidateId":"local","remoteCandidateId":"remote"},
 {"id":"local","type":"local-candidate","candidateType":"host"},
 {"id":"remote","type":"remote-candidate","candidateType":"relay"},
 {"id":"unselected","type":"candidate-pair","currentRoundTripTime":9}
]''';
List<Map<String, Object?>> reports() => (jsonDecode(_recorded) as List)
    .map((r) => (r as Map).cast<String, Object?>())
    .toList();

void main() {
  test(
    'recorded native getStats snapshots retain selected links and rates',
    () {
      final snapshots =
          jsonDecode(
                File(
                  'test/support/rtc_stats_recording.json',
                ).readAsStringSync(),
              )
              as List;
      final parser = StreamStatsParser();
      final samples = snapshots
          .map(
            (snapshot) => parser.parse(
              (snapshot['reports'] as List)
                  .map((r) => (r as Map).cast<String, Object?>())
                  .toList(),
              (snapshot['elapsedMs'] as num).toDouble(),
            )!,
          )
          .toList();
      expect(samples.first.codec, 'video/H265');
      expect(samples.first.bitrateKbps, isNull);
      expect(samples.last.width, 488);
      expect(samples.last.height, 1080);
      expect(samples.last.fps, 59);
      expect(samples.last.bitrateKbps, closeTo(6588 * 8 / 1016.954, 1e-9));
      expect(samples.last.decodeTimeMs, closeTo(262 / 60, 1e-9));
      expect(samples.last.jitterBufferDelayMs, closeTo(9.503 / 61, 1e-9));
      expect(samples.last.candidateType, isNotNull);
      expect(samples.last.rttMs, isNotNull);
    },
  );

  test('linked reports, delta rates and per-frame durations', () {
    final parser = StreamStatsParser();
    final first = parser.parse(reports(), 200)!;
    expect(first.bitrateKbps, isNull);
    expect(first.fps, isNull);
    expect(first.decodeTimeMs, isNull);
    expect(first.jitterBufferDelayMs, isNull);
    expect(first.rttMs, 40);
    expect(first.codec, 'video/H264');
    expect(first.candidateType, 'host/relay');
    expect(first.timeToFirstFrameMs, 200);
    final next = reports();
    next.first.addAll({
      'framesDecoded': 130,
      'bytesReceived': 200000,
      'jitterBufferDelay': 1.5,
      'jitterBufferEmittedCount': 130,
      'totalDecodeTime': 0.45,
      'packetsLost': 1,
    });
    final sample = parser.parse(next, 1200)!;
    expect(sample.fps, 30);
    expect(sample.bitrateKbps, 800);
    expect(sample.jitterBufferDelayMs, closeTo(10, 1e-9));
    expect(sample.decodeTimeMs, closeTo(5, 1e-9));
    expect(sample.packetsLost, 1);
    expect(sample.framesDropped, 3);
    expect(sample.freezeCount, 1);
    expect(sample.timeToFirstFrameMs, 200);
    expect(sample.width, 1080);
    expect(sample.height, 2400);
  });
  test('native numeric strings and nominated selected pair fallback', () {
    final native = reports()..removeWhere((r) => r['type'] == 'transport');
    native.first.remove('kind');
    native.first.addAll({'mediaType': 'video', 'framesPerSecond': '59.5'});
    native[2].addAll({
      'nominated': 'true',
      'state': 'succeeded',
      'currentRoundTripTime': '0.05',
    });
    final sample = StreamStatsParser().parse(native, 250)!;
    expect(sample.fps, 59.5);
    expect(sample.rttMs, 50);
    expect(sample.candidateType, 'host/relay');
  });
  test('sparse, stalled, reset and replaced reports never invent rates', () {
    final parser = StreamStatsParser();
    expect(parser.parse([], 0), isNull);
    final sparse = <Map<String, Object?>>[
      {'id': 'v', 'type': 'inbound-rtp', 'kind': 'video'},
    ];
    expect(parser.parse(sparse, 100)!.timeToFirstFrameMs, isNull);
    parser.parse(reports(), 200);
    final same = parser.parse(reports(), 1200)!;
    expect(same.fps, 0);
    expect(same.decodeTimeMs, isNull);
    final reset = reports();
    reset.first.addAll({'framesDecoded': 1, 'bytesReceived': 10});
    expect(parser.parse(reset, 2200)!.bitrateKbps, isNull);
    reset.first['id'] = 'replacement';
    expect(parser.parse(reset, 3200)!.fps, isNull);
    expect(StreamStatsParser().parse(reports(), 50)!.timeToFirstFrameMs, 50);
  });
  test('copy, equality, hash and typed overrides', () {
    const value = StreamStats(fps: 30, codec: 'video/H264');
    expect(value.copyWith(), value);
    expect(value.copyWith().hashCode, value.hashCode);
    expect(value.copyWith(codec: 'video/VP9').codec, 'video/VP9');
    expect(value.copyWith(fps: 60), isNot(value));
  });
  test(
    'stats publication, disconnect clearing and close cancels all polling',
    () async {
      final h = Harness();
      await h.connect();
      expect(h.session.stats.value, isNull);
      h.peer.stats = const VideoStats(
        width: 1080,
        height: 2400,
        framesDecoded: 10,
        sample: StreamStats(fps: 30),
      );
      h.peer.emitVideo(FakeMediaStream());
      await pump();
      await h.advance(500);
      expect(h.session.stats.value?.fps, 30);
      expect(h.session.stats.value?.timeToFirstFrameMs, isNotNull);
      h.peer.emitState(PeerState.disconnected);
      expect(h.session.stats.value, isNull);
      await h.advance(1000);
      expect(h.session.stats.value, isNull);
      await h.session.close();
      expect(h.peer.closed, isTrue);
      expect(h.ws.closedByClient, isTrue);
      expect(h.scheduler.pendingTimers, 0);
      await h.advance(60000);
      expect(h.session.stats.value, isNull);
      expect(h.scheduler.pendingTimers, 0);
    },
  );
  test(
    'a stats read completing after close cannot publish or rearm timers',
    () async {
      final h = Harness();
      await h.connect();
      final gate = h.peer.statsGate = Completer<VideoStats?>();
      h.peer.emitVideo(FakeMediaStream());
      await pump();
      await h.session.close();
      gate.complete(
        const VideoStats(
          width: 100,
          height: 200,
          framesDecoded: 1,
          sample: StreamStats(fps: 30),
        ),
      );
      await pump();
      expect(h.session.stats.value, isNull);
      expect(h.session.videoSize.value, isNull);
      expect(h.scheduler.pendingTimers, 0);
    },
  );
}
