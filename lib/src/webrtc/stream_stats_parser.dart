// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal W3C WebRTC parsing; durations are seconds in source reports.
// ignore_for_file: public_member_api_docs
import '../core/stream_stats.dart';
import '../core/stream_transports.dart';

final class StreamStatsParser {
  Map<String, Object?>? _previous;
  String? _previousId;
  double? _previousMs;

  VideoStats? read(
    Iterable<Map<String, Object?>> reports, {
    Duration? sampleTime,
    bool publishStats = false,
    bool resetRates = false,
    double? timeToFirstFrameMs,
  }) {
    final byId = <Object?, Map<String, Object?>>{};
    Map<String, Object?>? video, selectedPair;
    for (final report in reports) {
      byId[report['id']] = report;
      if (report['type'] == 'inbound-rtp' &&
          (report['kind'] ?? report['mediaType']) == 'video' &&
          report['isRemote'] != true) {
        video ??= report;
      }
      if (report['type'] == 'candidate-pair' && report['selected'] == true) {
        selectedPair ??= report;
      }
    }
    if (resetRates) {
      _previous = null;
      _previousId = null;
      _previousMs = null;
    }
    if (video == null) return null;
    double? number(Map<String, Object?>? r, String key) {
      final value = r?[key];
      final n = value is num ? value.toDouble() : double.tryParse('$value');
      return n?.isFinite == true ? n : null;
    }

    final width = number(video, 'frameWidth'),
        height = number(video, 'frameHeight');
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    StreamStats? sample;
    if (publishStats && sampleTime != null) {
      final elapsedMs = sampleTime.inMicroseconds / 1000;
      final previous = _previousId == video['id'] ? _previous : null;
      final dt = previous == null ? null : elapsedMs - _previousMs!;
      double? delta(String key) {
        final now = number(video, key), before = number(previous, key);
        if (dt == null ||
            dt <= 0 ||
            now == null ||
            before == null ||
            now < before) {
          return null;
        }
        return now - before;
      }

      double? perFrame(String total, String count) {
        final duration = delta(total), frames = delta(count);
        return duration == null || frames == null || frames <= 0
            ? null
            : duration * 1000 / frames;
      }

      final transport = byId[video['transportId']];
      final linked = byId[transport?['selectedCandidatePairId']];
      final pair = linked?['type'] == 'candidate-pair' ? linked : selectedPair;
      String? candidate(String field) {
        final type = byId[pair?[field]]?['candidateType'];
        return const ['host', 'srflx', 'prflx', 'relay'].contains(type)
            ? type as String
            : null;
      }

      final codec = byId[video['codecId']]?['mimeType'];
      final frames = delta('framesDecoded'), bytes = delta('bytesReceived');
      sample = StreamStats(
        fps:
            number(video, 'framesPerSecond') ??
            (frames == null ? null : frames * 1000 / dt!),
        width: width.toInt(),
        height: height.toInt(),
        codec: codec is String ? codec : null,
        bitrateKbps: bytes == null ? null : bytes * 8 / dt!,
        rttMs: number(pair, 'currentRoundTripTime') == null
            ? null
            : number(pair, 'currentRoundTripTime')! * 1000,
        jitterBufferDelayMs: perFrame(
          'jitterBufferDelay',
          'jitterBufferEmittedCount',
        ),
        packetsLost: number(video, 'packetsLost')?.toInt(),
        framesDropped: number(video, 'framesDropped')?.toInt(),
        freezeCount: number(video, 'freezeCount')?.toInt(),
        decodeTimeMs: perFrame('totalDecodeTime', 'framesDecoded'),
        localCandidateType: candidate('localCandidateId'),
        remoteCandidateType: candidate('remoteCandidateId'),
        timeToFirstFrameMs: timeToFirstFrameMs,
      );
      _previous = Map.of(video);
      _previousId = video['id'] is String ? video['id'] as String : null;
      _previousMs = elapsedMs;
    }
    return VideoStats(
      width: width.toInt(),
      height: height.toInt(),
      framesDecoded: number(video, 'framesDecoded')?.toInt() ?? 0,
      sample: sample,
    );
  }
}
