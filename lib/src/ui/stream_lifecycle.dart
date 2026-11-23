// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../core/device_stream_session.dart';

/// Lifecycle adapter for headless or custom UI integrations.
///
/// Uses Flutter app lifecycle and connectivity_plus by default. A supplied
/// connectivity stream replaces the platform source. Initial foreground/online
/// snapshots never wake the session. The
/// embedding UI creates this adapter once alongside its session and disposes it
/// with that session. Change connectivity sources with [updateConnectivity].
final class StreamLifecycle {
  /// Attaches app lifecycle and the default or supplied online/offline source.
  StreamLifecycle({required this.session, Stream<bool>? connectivity}) {
    _listener = AppLifecycleListener(onStateChange: _onState);
    final initial = WidgetsBinding.instance.lifecycleState;
    _foreground =
        initial != AppLifecycleState.hidden &&
        initial != AppLifecycleState.paused &&
        initial != AppLifecycleState.detached;
    session.setVisible(_foreground);
    updateConnectivity(connectivity);
  }

  /// Session whose keepAlive and reconnects are adapted.
  final DeviceStreamSession session;
  late final AppLifecycleListener _listener;
  StreamSubscription<bool>? _network;
  bool _usesDefault = false;
  int _networkEpoch = 0;
  int _observation = 0;
  bool _foreground = true;
  bool _disposed = false;

  void _onState(AppLifecycleState state) {
    if (_disposed) return;
    // Inactive can still be visible (for example a system overlay or lost
    // window focus). Only actual hidden/background states pause the stream.
    if (state == AppLifecycleState.inactive) return;
    if (state == AppLifecycleState.resumed && _usesDefault) {
      unawaited(_refreshNetwork(_networkEpoch));
    }
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    session.setVisible(foreground);
  }

  /// Replaces the source, retaining the last observed availability.
  /// Null restores the default platform source. Late old-source events are ignored.
  void updateConnectivity(Stream<bool>? connectivity) {
    if (_disposed) return;
    final epoch = ++_networkEpoch;
    unawaited(_network?.cancel().catchError((Object _) {}));
    _usesDefault = connectivity == null;
    final source =
        connectivity ?? Connectivity().onConnectivityChanged.map(_available);
    _network = source.listen(
      (online) {
        if (_disposed || epoch != _networkEpoch) return;
        _observation++;
        session.setNetworkAvailable(online);
      },
      onError: (Object _) {
        // An observation failure is unknown; retain the last known availability.
        if (!_disposed && epoch == _networkEpoch) _observation++;
      },
    );
    if (_usesDefault) unawaited(_refreshNetwork(epoch));
  }

  static bool _available(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  Future<void> _refreshNetwork(int epoch) async {
    final observation = ++_observation;
    try {
      final results = await Connectivity().checkConnectivity();
      if (_disposed || epoch != _networkEpoch || observation != _observation) {
        return;
      }
      session.setNetworkAvailable(_available(results));
    } on Object {
      // No polling or retry on plugin failures: availability remains unknown.
    }
  }

  /// Detaches without closing the session. Its owner must replace the network
  /// observer or explicitly set session availability if the session continues.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _networkEpoch++;
    _listener.dispose();
    unawaited(_network?.cancel().catchError((Object _) {}));
  }
}
