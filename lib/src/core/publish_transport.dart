// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'publish.dart';

/// Optional upstream extension; existing receive-only custom transports still work.
abstract interface class PublishPeerTransport {
  /// Kinds with valid first-offer SSRC and codec reservations.
  Set<PublishKind> get publishKinds;

  /// Replaces a reserved sender's track. Null detaches without renegotiation.
  Future<void> replacePublishTrack(PublishKind kind, MediaStreamTrack? track);

  /// Whether the answer left every requested sender usable.
  Future<bool> canAttachPublish(List<PublishKind> kinds);
}

/// Owns local capture until release; no app-owned tracks are borrowed.
abstract interface class PublishMedia {
  /// Exactly the requested inputs.
  List<MediaStreamTrack> get tracks;

  /// Stops every input, including partial acquisitions. Idempotent.
  Future<void> stop();
}

/// Capture boundary, injectable alongside signaling and peers for tests.
abstract interface class PublishCapture {
  /// Requests default local inputs, detached from the peer.
  Future<PublishMedia> capture(
    PublishOptions options, {
    required bool Function() isCancelled,
    required void Function(PublishMedia media) onAcquired,
  });
}
