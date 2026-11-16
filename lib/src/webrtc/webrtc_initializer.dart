// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_webrtc/flutter_webrtc.dart';

Future<void>? _initialization;

/// Initializes native WebRTC once, before any renderer or peer connection.
/// Enables zero playout delay and allows a failed initialization to be retried.
Future<void> ensureWebRtcInitialized() => _initialization ??= _initialize();

Future<void> _initialize() async {
  try {
    await WebRTC.initialize(options: {'zeroPlayoutDelay': true});
  } on Object {
    _initialization = null;
    rethrow;
  }
}
