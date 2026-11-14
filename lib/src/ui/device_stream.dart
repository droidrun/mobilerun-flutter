// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/device_stream_session.dart';
import '../core/reconnect_policy.dart';
import '../core/stream_status.dart';
import '../widgets/device_stream_view.dart';
import 'stream_button.dart';
import 'stream_labels.dart';
import 'stream_lifecycle.dart';
import 'stream_status_pill.dart';
import 'stream_theme.dart';

/// State passed to overlay slots inside the bounded stream container.
final class StreamOverlayState {
  /// Creates an overlay state.
  const StreamOverlayState({
    this.status = const StreamConnecting(),
    this.labels = const StreamLabels(),
    required this.retry,
  });

  /// Current session state.
  final StreamStatus status;

  /// Localized strings.
  final StreamLabels labels;

  /// Retry a session which exhausted its attempts.
  final VoidCallback retry;

  /// Connecting or reconnecting text with attempt placeholders replaced.
  String get label => switch (status) {
    StreamReconnecting(:final attempt) when attempt > 1 =>
      labels.reconnectingAttempt
          .replaceAll('{attempt}', '$attempt')
          .replaceAll('{max}', '${ReconnectPolicy.maxAttempts}'),
    StreamReconnecting() => labels.reconnecting,
    _ => labels.connecting,
  };
}

/// A replacement overlay slot.
typedef StreamOverlayBuilder =
    Widget Function(BuildContext context, StreamOverlayState state);

/// One navigation state object shared by the default and custom bar.
final class StreamNavigationState {
  /// Creates navigation state.
  const StreamNavigationState({
    this.canControl = true,
    this.labels = const StreamLabels(),
    required this.onAction,
  });

  /// Same local input switch used by the view.
  final bool canControl;

  /// Localized accessible button labels.
  final StreamLabels labels;

  /// Sends an explicit Back, Home or Recent action.
  final ValueChanged<DeviceSystemKey> onAction;
}

/// Builds navigation under the video.
typedef StreamNavigationBuilder =
    Widget Function(BuildContext context, StreamNavigationState state);

/// Default navigation slot.
Widget defaultStreamNavigation(
  BuildContext context,
  StreamNavigationState state,
) => StreamNavigationBar(state: state);

/// Default corner placeholder, positioned within the stream container.
Widget defaultStreamPlaceholder(
  BuildContext context,
  StreamOverlayState state,
) => Align(
  alignment: Alignment.bottomLeft,
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: StreamStatusPill(label: state.label),
  ),
);

/// Default unavailable message and retry action.
Widget defaultStreamUnavailable(
  BuildContext context,
  StreamOverlayState state,
) {
  final t = StreamTheme.of(context);
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.wifi_off,
          size: 40,
          color: t.mutedForeground.withValues(alpha: .5),
        ),
        const SizedBox(height: 12),
        Text(
          state.labels.unavailable,
          style: t.typography.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: t.mutedForeground,
          ),
        ),
        const SizedBox(height: 12),
        StreamButton(
          label: state.labels.retry,
          icon: Icons.refresh,
          outline: true,
          onPressed: state.retry,
        ),
      ],
    ),
  );
}

/// Native Back/Home/Recent bar. The device service decides actual permissions.
class StreamNavigationBar extends StatelessWidget {
  /// Creates the bar from a single state object.
  const StreamNavigationBar({super.key, required this.state});

  /// Navigation actions and current local input configuration.
  final StreamNavigationState state;
  @override
  Widget build(BuildContext context) {
    final t = StreamTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.background,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            for (final item in [
              (DeviceSystemKey.back, Icons.chevron_left, state.labels.back),
              (DeviceSystemKey.home, Icons.home_outlined, state.labels.home),
              (DeviceSystemKey.recent, Icons.grid_view, state.labels.recent),
            ])
              Expanded(
                child: StreamButton(
                  label: item.$3,
                  icon: item.$2,
                  ghost: true,
                  onPressed: state.canControl
                      ? () => state.onAction(item.$1)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Device video/input with replaceable white-label default chrome.
/// The embedding app owns session start and close.
class DeviceStream extends StatefulWidget {
  /// Creates a bounded stream composite. Every slot has explicit default content.
  const DeviceStream({
    super.key,
    required this.session,
    this.hasControl = true,
    this.autofocus = false,
    this.labels = const StreamLabels(),
    this.controller,
    this.placeholderBuilder = defaultStreamPlaceholder,
    this.unavailableBuilder = defaultStreamUnavailable,
    this.navigationBuilder = defaultStreamNavigation,
    this.connectivity,
    this.observeLifecycle = true,
  });

  /// Session supplying video and state.
  final DeviceStreamSession session;

  /// Local input switch, never a backend permission decision.
  final bool hasControl;

  /// Requests hardware keyboard focus when mounted.
  final bool autofocus;

  /// Overrides built-in text.
  final StreamLabels labels;

  /// Optional keyboard/navigation handle.
  final DeviceStreamController? controller;

  /// Connecting/reconnecting overlay with container scope.
  final StreamOverlayBuilder placeholderBuilder;

  /// Unavailable overlay with retry and container scope.
  final StreamOverlayBuilder unavailableBuilder;

  /// Navigation slot receiving one state object.
  final StreamNavigationBuilder navigationBuilder;

  /// Optional existing host connectivity source.
  final Stream<bool>? connectivity;

  /// Uses the lifecycle adapter by default; disable when the app already owns it.
  final bool observeLifecycle;
  @override
  State<DeviceStream> createState() => _DeviceStreamState();
}

class _DeviceStreamState extends State<DeviceStream> {
  final _controller = DeviceStreamController();
  StreamLifecycle? _lifecycle;
  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    if (widget.observeLifecycle) {
      _lifecycle = StreamLifecycle(
        session: widget.session,
        connectivity: widget.connectivity,
      );
    }
  }

  @override
  void didUpdateWidget(DeviceStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.observeLifecycle != widget.observeLifecycle) {
      _lifecycle?.dispose();
      _lifecycle = null;
      _attach();
    } else if (oldWidget.connectivity != widget.connectivity) {
      _lifecycle?.updateConnectivity(widget.connectivity);
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = StreamTheme.of(context);
    final controller = widget.controller ?? _controller;
    return DefaultTextStyle(
      style: t.typography.copyWith(inherit: false, color: t.foreground),
      child: ValueListenableBuilder<StreamStatus>(
        valueListenable: widget.session.status,
        builder: (context, status, _) {
          final unavailable = status is StreamUnavailable;
          final canControl = widget.hasControl && !unavailable;
          final scope = StreamOverlayState(
            status: status,
            labels: widget.labels,
            retry: widget.session.retry,
          );
          return ColoredBox(
            color: t.background,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DeviceStreamView(
                        session: widget.session,
                        hasControl: canControl,
                        autofocus: widget.autofocus,
                        controller: controller,
                      ),
                      if (unavailable)
                        widget.unavailableBuilder(context, scope)
                      else if (status is! StreamConnected)
                        widget.placeholderBuilder(context, scope),
                    ],
                  ),
                ),
                widget.navigationBuilder(
                  context,
                  StreamNavigationState(
                    canControl: canControl,
                    labels: widget.labels,
                    onAction: (key) {
                      if (canControl) controller.sendSystemKey(key);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
