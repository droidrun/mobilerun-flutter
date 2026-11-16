// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/stream_transports.dart';
import 'package:mobilerun_flutter/src/webrtc/stream_stats_parser.dart';

import 'support/fake_transports.dart';
import 'support/harness.dart';

List<Map<String, Object?>> reports(int index) {
  final snapshots =
      jsonDecode(
            File('test/support/rtc_stats_recording.json').readAsStringSync(),
          )
          as List;
  return (snapshots[index]['reports'] as List)
      .map((r) => (r as Map).cast<String, Object?>())
      .toList();
}

StreamStats sample(
  StreamStatsParser parser,
  List<Map<String, Object?>> reports,
  int ms,
) => parser
    .read(
      reports,
      sampleTime: Duration(milliseconds: ms),
      publishStats: true,
      timeToFirstFrameMs: 75,
    )!
    .sample!;

const video = VideoStats(
  width: 100,
  height: 200,
  framesDecoded: 1,
  sample: StreamStats(fps: 30),
);
Future<void> attachVideo(Harness h) async {
  h.peer.stats = video;
  h.peer.emitVideo(FakeMediaStream());
  await pump();
}

Future<void> second(Harness h) async {
  await h.advance(500);
  await h.advance(500);
}

void main() {
  test('recorded native links, rates and supplied TTFF', () {
    final parser = StreamStatsParser();
    final first = sample(parser, reports(0), 200);
    final last = parser
        .read(
          reports(1),
          sampleTime: const Duration(microseconds: 1216954),
          publishStats: true,
          timeToFirstFrameMs: 75,
        )!
        .sample!;
    expect(first.bitrateKbps, isNull);
    expect(last.width, 488);
    expect(last.height, 1080);
    expect(last.fps, 59);
    expect(last.bitrateKbps, closeTo(51.8253529658, 1e-9));
    expect(last.decodeTimeMs, closeTo(4.3666666667, 1e-9));
    expect(last.jitterBufferDelayMs, closeTo(0.1557868852, 1e-9));
    expect(last.codec, 'video/H265');
    expect(last.packetsLost, 0);
    expect(last.framesDropped, 2);
    expect(last.freezeCount, 0);
    expect(last.localCandidateType, 'relay');
    expect(last.remoteCandidateType, 'prflx');
    expect(last.rttMs, 19);
    expect(last.timeToFirstFrameMs, 75);
  });
  test('nominated is insufficient; selected true is a valid fallback', () {
    final native = reports(0)..removeWhere((r) => r['type'] == 'transport');
    native[2].addAll({'nominated': true, 'state': 'succeeded'});
    final unselected = sample(StreamStatsParser(), native, 1000);
    expect(unselected.localCandidateType, isNull);
    expect(unselected.remoteCandidateType, isNull);
    expect(unselected.rttMs, isNull);
    native[2]['selected'] = true;
    final selected = sample(StreamStatsParser(), native, 1000);
    expect(selected.localCandidateType, 'relay');
    expect(selected.remoteCandidateType, 'prflx');
    expect(selected.rttMs, 19);
  });
  test('size-only reads do not calculate or advance rate baselines', () {
    final parser = StreamStatsParser();
    sample(parser, reports(0), 200);
    expect(
      parser
          .read(reports(1), sampleTime: const Duration(milliseconds: 700))!
          .sample,
      isNull,
    );
    final last = sample(parser, reports(1), 1200);
    expect(last.bitrateKbps, 52.704);
    expect(parser.read(reports(1), resetRates: true)!.sample, isNull);
    expect(sample(parser, reports(1), 2200).bitrateKbps, isNull);
  });
  test('malformed optional fields retain dimensions and sparse sample', () {
    final native = reports(0);
    native[1]['mimeType'] = 42;
    native.first['packetsLost'] = [];
    native.first['framesPerSecond'] = 'NaN';
    native[3]['currentRoundTripTime'] = double.infinity;
    final parsed = StreamStatsParser().read(
      native,
      publishStats: true,
      sampleTime: const Duration(seconds: 1),
    )!;
    expect(parsed.width, 488);
    expect(parsed.height, 1080);
    expect(parsed.sample!.codec, isNull);
    expect(parsed.sample!.packetsLost, isNull);
    expect(parsed.sample!.fps, isNull);
    expect(parsed.sample!.rttMs, isNull);
  });
  test('reset counters and replaced inbound ids do not invent rates', () {
    final parser = StreamStatsParser();
    expect(parser.read([]), isNull);
    sample(parser, reports(1), 1000);
    expect(sample(parser, reports(0), 2000).bitrateKbps, isNull);
    final replaced = reports(1);
    replaced.first['id'] = 'replacement';
    replaced.first.remove('framesPerSecond');
    expect(sample(parser, replaced, 3000).fps, isNull);
  });
  test('value equality deduplicates notifier samples', () {
    expect(const StreamStats(fps: 30), const StreamStats(fps: 30));
    expect(
      const StreamStats(fps: 30).hashCode,
      const StreamStats(fps: 30).hashCode,
    );
    expect(const StreamStats(fps: 31), isNot(const StreamStats(fps: 30)));
  });
  test(
    'sampling requires observer, visibility and connected session',
    () async {
      final h = Harness();
      addTearDown(h.session.close);
      await h.connect();
      await attachVideo(h);
      await second(h);
      expect(h.session.stats.value, isNull);
      expect(h.peer.sampleTimes, isEmpty);
      var emissions = 0;
      void listen() {
        if (h.session.stats.value != null) emissions++;
      }

      h.session.stats.addListener(listen);
      await h.advance(500);
      expect(emissions, 0);
      await h.advance(500);
      expect(emissions, 1);
      h.peer.stats = const VideoStats(
        width: 100,
        height: 200,
        framesDecoded: 2,
        sample: StreamStats(fps: 31),
      );
      await second(h);
      expect(emissions, 2);
      expect(h.peer.sampleTimes, [
        const Duration(seconds: 2),
        const Duration(seconds: 3),
      ]);
      h.session.setVisible(false);
      expect(h.session.stats.value, isNull);
      await second(h);
      expect(emissions, 2);
      h.session.setVisible(true);
      await second(h);
      expect(emissions, 3);
      h.session.stats.removeListener(listen);
      expect(h.session.stats.value, isNull);
      final ticks = h.peer.sampleTimes.length;
      await second(h);
      expect(h.peer.sampleTimes.length, ticks);
      h.session.stats.addListener(listen);
      h.peer.emitState(PeerState.disconnected);
      expect(h.session.stats.value, isNull);
      await second(h);
      expect(h.session.stats.value, isNull);
    },
  );
  test('exhausted retry budget clears a previously published sample', () async {
    final h = Harness();
    addTearDown(h.session.close);
    h.session.stats.addListener(() {});
    await h.connect();
    await attachVideo(h);
    await second(h);
    expect(h.session.stats.value!.fps, 30);
    h.connector.failWith = StateError('offline');
    h.peer.emitState(PeerState.failed);
    await pump();
    for (final _ in const [1, 2, 3, 4, 5, 6]) {
      h.session.wake();
      await pump();
    }
    expect(h.session.status.value, const StreamUnavailable());
    expect(h.session.stats.value, isNull);
    expect(h.scheduler.pendingTimers, 0);
  });

  test(
    'first decoded frame is stamped by the injected attempt clock at 50ms',
    () async {
      final h = Harness();
      addTearDown(h.session.close);
      await h.connect();
      h.peer.stats = const VideoStats(
        width: 100,
        height: 200,
        framesDecoded: 0,
      );
      h.peer.emitVideo(FakeMediaStream());
      await pump();
      await h.advance(49);
      h.peer.stats = video;
      await h.advance(1);
      await h.advance(500);
      expect(h.peer.lastTimeToFirstFrameMs, 50);
    },
  );
  test('suppressed ICE dip samples by session status', () async {
    final h = Harness();
    addTearDown(h.session.close);
    await h.connect();
    h.session.stats.addListener(() {});
    await attachVideo(h);
    h.ws.receive(example('server-rtc-configuration.json'));
    await pump();
    h.peer.emitState(PeerState.connecting);
    expect(h.session.status.value, const StreamConnected());
    await second(h);
    expect(h.session.stats.value!.fps, 30);
  });
  test(
    'slow and failing reads serialize, continue, and stay silent after close',
    () async {
      final h = Harness();
      await h.connect();
      h.session.stats.addListener(() {});
      final peer = h.peer;
      final gate = peer.statsGate = Completer<VideoStats?>();
      peer.emitVideo(FakeMediaStream());
      await pump();
      await h.advance(5000);
      expect(peer.reads, 1);
      expect(peer.maxActiveReads, 1);
      peer.statsGate = null;
      gate.complete(video);
      await pump();
      peer.statsError = StateError('bad report');
      await h.advance(0);
      final failedReads = peer.reads;
      peer.statsError = null;
      peer.stats = video;
      await h.advance(500);
      expect(peer.reads, greaterThan(failedReads));
      expect(h.session.videoSize.value, const VideoSize(100, 200));
      final late = peer.statsGate = Completer<VideoStats?>();
      await h.advance(500);
      await h.session.close();
      late.complete(video);
      await pump();
      expect(h.session.stats.value, isNull);
      expect(h.session.videoSize.value, isNull);
      expect(h.scheduler.pendingTimers, 0);
      expect(peer.maxActiveReads, 1);
      expect(h.ws.closeCode, 1000);
    },
  );
}
