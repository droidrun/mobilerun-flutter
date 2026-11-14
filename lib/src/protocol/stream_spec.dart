// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

/// Options of a negotiated WebRTC data channel.
final class DataChannelSpec {
  /// Creates a channel description.
  const DataChannelSpec({
    required this.label,
    required this.id,
    required this.ordered,
    this.maxRetransmits,
  });

  /// The channel label.
  final String label;

  /// The negotiated channel id.
  final int id;

  /// Whether both peers create the channel with this id instead of announcing
  /// it in band. Always true for the stream channels.
  final bool negotiated = true;

  /// Whether messages arrive in order.
  final bool ordered;

  /// The retransmit limit, or null for a reliable channel.
  final int? maxRetransmits;
}

/// The two negotiated data channels of a stream.
abstract final class StreamDataChannels {
  StreamDataChannels._();

  /// Reliable and ordered; carries every binary control message.
  static const DataChannelSpec control = DataChannelSpec(
    label: 'control',
    id: 1,
    ordered: true,
  );

  /// Unordered without retransmits; carries hover messages only.
  static const DataChannelSpec hover = DataChannelSpec(
    label: 'hover',
    id: 2,
    ordered: false,
    maxRetransmits: 0,
  );
}
