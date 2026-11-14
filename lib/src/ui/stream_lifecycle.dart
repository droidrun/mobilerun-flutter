// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/device_stream_session.dart';

/// Lifecycle adapter for headless or custom UI integrations.
///
/// Uses Flutter app lifecycle and optionally the host's existing connectivity
/// stream. Initial foreground/online snapshots never wake the session. The
/// embedding UI creates this adapter once alongside its session and disposes it
/// with that session. Change connectivity sources with [updateConnectivity].
final class StreamLifecycle {
  /// Attaches app lifecycle and an optional online/offline source.
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
  bool _foreground = true;
  bool? _online;
  bool _disposed = false;

  void _onState(AppLifecycleState state) {
    if (_disposed) return;
    // Inactive can still be visible (for example a system overlay or lost
    // window focus). Only actual hidden/background states pause the stream.
    if (state == AppLifecycleState.inactive) return;
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    session.setVisible(foreground);
  }

  /// Replaces only the subscription, retaining the last known online state.
  /// A new source reporting online after a known offline state wakes the session.
  void updateConnectivity(Stream<bool>? connectivity) {
    if (_disposed) return;
    unawaited(_network?.cancel().catchError((Object _) {}));
    _network = connectivity?.listen(_onNetwork, onError: (Object _) {});
  }

  void _onNetwork(bool online) {
    if (_disposed) return;
    final wasOnline = _online;
    _online = online;
    if (wasOnline == false && online) session.wake();
  }

  /// Detaches this adapter without closing its app-owned session.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listener.dispose();
    unawaited(_network?.cancel().catchError((Object _) {}));
  }
}
