// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// One initializer shared by renderers and peer connections.
final webRtcInitializer = WebRtcInitializer(WebRTC.initialize);

/// Serializes native WebRTC initialization before the first plugin resource.
final class WebRtcInitializer {
  /// Injects the native initialization call for tests.
  WebRtcInitializer(this._initialize);

  final Future<void> Function({Map<String, dynamic>? options}) _initialize;
  Future<void>? _initialization;

  bool _initialized = false;

  /// Always enables zero playout delay. Failures propagate to the caller.
  Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    return _initialization ??= _run();
  }

  Future<void> _run() async {
    try {
      await _initialize(options: {'zeroPlayoutDelay': true});
      _initialized = true;
    } on Object {
      _initialization = null;
      rethrow;
    }
  }
}
