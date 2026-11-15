// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Internal W3C WebRTC stats parsing; durations are seconds in source reports.
// ignore_for_file: public_member_api_docs
import '../core/stream_stats.dart';

final class StreamStatsParser {
  Map<String, Object?>? _previous;
  String? _previousId;
  double? _previousMs;
  double? _firstFrameMs;

  StreamStats? parse(List<Map<String, Object?>> reports, double elapsedMs) {
    final byId = {for (final r in reports) r['id']: r};
    final videos = reports
        .where(
          (r) =>
              r['type'] == 'inbound-rtp' &&
              (r['kind'] ?? r['mediaType']) == 'video' &&
              r['isRemote'] != true,
        )
        .toList();
    if (videos.isEmpty) return null;
    final video = videos.first;
    double? number(Map<String, Object?>? r, String key) {
      final value = r?[key];
      final n = value is num ? value.toDouble() : double.tryParse('$value');
      return n?.isFinite == true ? n : null;
    }

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

    if ((number(video, 'framesDecoded') ?? 0) > 0) _firstFrameMs ??= elapsedMs;
    final transport = byId[video['transportId']];
    Map<String, Object?>? pair = byId[transport?['selectedCandidatePairId']];
    // Older native reports expose selected/nominated instead of a transport link.
    if (pair == null) {
      for (final r in reports) {
        if (r['type'] == 'candidate-pair' &&
            (r['selected'] == true ||
                r['selected'] == 'true' ||
                ((r['nominated'] == true || r['nominated'] == 'true') &&
                    r['state'] == 'succeeded'))) {
          pair = r;
          break;
        }
      }
    }
    String? candidate(String field) {
      final type = byId[pair?[field]]?['candidateType'];
      return const ['host', 'srflx', 'prflx', 'relay'].contains(type)
          ? type as String
          : null;
    }

    final frames = delta('framesDecoded'), bytes = delta('bytesReceived');
    final result = StreamStats(
      fps:
          number(video, 'framesPerSecond') ??
          (frames == null ? null : frames * 1000 / dt!),
      width: number(video, 'frameWidth')?.toInt(),
      height: number(video, 'frameHeight')?.toInt(),
      codec: byId[video['codecId']]?['mimeType'] as String?,
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
      timeToFirstFrameMs: _firstFrameMs,
    );
    _previous = Map.of(video);
    _previousId = video['id'] as String?;
    _previousMs = elapsedMs;
    return result;
  }
}
