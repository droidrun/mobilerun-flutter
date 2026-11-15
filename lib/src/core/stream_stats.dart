// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// An immutable inbound-video sample. Unsupported fields and the first sample's
/// counter rates are null. Reconnecting resets rates and first-frame timing.
final class StreamStats {
  /// Creates a sample. Optional named fields allow compatible extensions.
  const StreamStats({
    this.fps,
    this.width,
    this.height,
    this.codec,
    this.bitrateKbps,
    this.rttMs,
    this.jitterBufferDelayMs,
    this.packetsLost,
    this.framesDropped,
    this.freezeCount,
    this.decodeTimeMs,
    this.localCandidateType,
    this.remoteCandidateType,
    this.timeToFirstFrameMs,
  });

  /// Decoded frames per second.
  final double? fps;

  /// Decoded video width in pixels.
  final int? width;

  /// Decoded video height in pixels.
  final int? height;

  /// Inbound codec MIME type.
  final String? codec;

  /// Inbound video payload kilobits per second.
  final double? bitrateKbps;

  /// Selected ICE pair round trip in milliseconds.
  final double? rttMs;

  /// Jitter buffer delay per emitted frame in this sample.
  final double? jitterBufferDelayMs;

  /// Cumulative lost packets; late arrivals may reduce this counter.
  final int? packetsLost;

  /// Cumulative dropped frames.
  final int? framesDropped;

  /// Cumulative freezes, when reported by the platform.
  final int? freezeCount;

  /// Decode milliseconds per decoded frame in this sample.
  final double? decodeTimeMs;

  /// Local candidate: host, srflx, prflx or relay.
  final String? localCandidateType;

  /// Remote candidate: host, srflx, prflx or relay.
  final String? remoteCandidateType;

  /// Attempt start to first observed decoded frame, in milliseconds.
  final double? timeToFirstFrameMs;

  /// Selected local/remote types; null unless both are available.
  String? get candidateType =>
      localCandidateType == null || remoteCandidateType == null
      ? null
      : '$localCandidateType/$remoteCandidateType';

  /// Copies this sample with non-null overrides, retaining omitted fields.
  StreamStats copyWith({
    double? fps,
    int? width,
    int? height,
    String? codec,
    double? bitrateKbps,
    double? rttMs,
    double? jitterBufferDelayMs,
    int? packetsLost,
    int? framesDropped,
    int? freezeCount,
    double? decodeTimeMs,
    String? localCandidateType,
    String? remoteCandidateType,
    double? timeToFirstFrameMs,
  }) => StreamStats(
    fps: fps ?? this.fps,
    width: width ?? this.width,
    height: height ?? this.height,
    codec: codec ?? this.codec,
    bitrateKbps: bitrateKbps ?? this.bitrateKbps,
    rttMs: rttMs ?? this.rttMs,
    jitterBufferDelayMs: jitterBufferDelayMs ?? this.jitterBufferDelayMs,
    packetsLost: packetsLost ?? this.packetsLost,
    framesDropped: framesDropped ?? this.framesDropped,
    freezeCount: freezeCount ?? this.freezeCount,
    decodeTimeMs: decodeTimeMs ?? this.decodeTimeMs,
    localCandidateType: localCandidateType ?? this.localCandidateType,
    remoteCandidateType: remoteCandidateType ?? this.remoteCandidateType,
    timeToFirstFrameMs: timeToFirstFrameMs ?? this.timeToFirstFrameMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamStats &&
          fps == other.fps &&
          width == other.width &&
          height == other.height &&
          codec == other.codec &&
          bitrateKbps == other.bitrateKbps &&
          rttMs == other.rttMs &&
          jitterBufferDelayMs == other.jitterBufferDelayMs &&
          packetsLost == other.packetsLost &&
          framesDropped == other.framesDropped &&
          freezeCount == other.freezeCount &&
          decodeTimeMs == other.decodeTimeMs &&
          localCandidateType == other.localCandidateType &&
          remoteCandidateType == other.remoteCandidateType &&
          timeToFirstFrameMs == other.timeToFirstFrameMs;

  @override
  int get hashCode => Object.hashAll([
    fps,
    width,
    height,
    codec,
    bitrateKbps,
    rttMs,
    jitterBufferDelayMs,
    packetsLost,
    framesDropped,
    freezeCount,
    decodeTimeMs,
    localCandidateType,
    remoteCandidateType,
    timeToFirstFrameMs,
  ]);
}
