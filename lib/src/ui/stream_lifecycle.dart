// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/device_stream_session.dart';

/// Lifecycle adapter for headless or custom UI integrations.
///
/// Uses Flutter app lifecycle and optionally the host's existing connectivity
/// stream. Initial foreground/online snapshots never wake the session. The
/// embedding UI owns this adapter's lifetime alongside its session.
final class StreamLifecycle {
  /// Attaches app lifecycle and an optional online/offline source.
  StreamLifecycle({required this.session, Stream<bool>? connectivity}) {
    _listener = AppLifecycleListener(onStateChange: _onState);
    final initial = WidgetsBinding.instance.lifecycleState;
    _foreground = initial == null || initial == AppLifecycleState.resumed;
    session.setVisible(_foreground);
    _network = connectivity?.listen(_onNetwork, onError: (Object _) {});
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
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    session.setVisible(foreground);
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
