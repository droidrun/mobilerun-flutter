// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/device_stream_session.dart';
import '../core/publish.dart';
import '../core/stream_status.dart';
import 'stream_labels.dart';
import 'stream_theme.dart';

/// Internal floating control using the same isolated tokens as the default UI.
class StreamPublishPill extends StatefulWidget {
  /// Creates the capability-backed input controls.
  const StreamPublishPill({
    super.key,
    required this.session,
    required this.labels,
  });

  /// Session owning capture and signaling.
  final DeviceStreamSession session;

  /// Overridable visible and accessible text.
  final StreamLabels labels;
  @override
  State<StreamPublishPill> createState() => _StreamPublishPillState();
}

class _StreamPublishPillState extends State<StreamPublishPill> {
  bool _changing = false;
  bool _faded = false;
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    _activity();
  }

  void _activity() {
    _fadeTimer?.cancel();
    if (_faded) setState(() => _faded = false);
    _fadeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _faded = true);
    });
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggle(bool camera) async {
    if (_changing) return;
    final session = widget.session;
    final previous = session.publishState.value;
    setState(() => _changing = true);
    try {
      if (previous.phase == PublishPhase.active) {
        await session.stopPublish();
        if (!camera || !mounted || widget.session != session) return;
        await session.startPublish(
          PublishOptions(
            audio: true,
            video: !previous.kinds.contains(PublishKind.video),
          ),
        );
      } else {
        await session.startPublish(PublishOptions(audio: true, video: camera));
      }
    } on PublishException {
      // The observable terminal state supplies the localized error label.
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.session.publishState,
      widget.session.status,
      widget.session.closed,
      widget.session.publishCameraAvailable,
    ]),
    builder: (context, _) {
      final t = StreamTheme.of(context);
      final labels = widget.labels;
      final state = widget.session.publishState.value;
      if (state.reason == 'publish_unsupported') return const SizedBox.shrink();
      final active = state.phase == PublishPhase.active;
      final video = active && state.kinds.contains(PublishKind.video);
      final pending =
          _changing ||
          {
            PublishPhase.capturing,
            PublishPhase.starting,
            PublishPhase.accepted,
          }.contains(state.phase);
      final enabled =
          !pending &&
          !widget.session.closed.value &&
          widget.session.status.value is StreamConnected;
      final error = switch (state.reason) {
        'permission_denied' => labels.publishPermissionDenied,
        'publish_not_allowed' => labels.publishNotAllowed,
        _ => state.phase == PublishPhase.error ? labels.publishFailed : null,
      };
      Widget button({required bool camera, required bool live}) {
        final label = camera
            ? (live ? labels.stopCamera : labels.camera)
            : (live ? labels.stopMicrophone : labels.microphone);
        return Semantics(
          toggled: live,
          child: Material(
            type: MaterialType.transparency,
            child: IconButton(
              tooltip: label,
              color: live ? t.destructive : t.foreground,
              disabledColor: t.mutedForeground,
              onPressed: enabled ? () => unawaited(_toggle(camera)) : null,
              icon: Icon(
                camera
                    ? (live ? Icons.videocam : Icons.videocam_off)
                    : (live ? Icons.mic : Icons.mic_off),
              ),
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null || pending)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error ?? labels.publishStarting,
                  key: const ValueKey('publish-status'),
                  textAlign: TextAlign.center,
                  style: t.typography.copyWith(
                    color: error == null ? t.mutedForeground : t.destructive,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          MouseRegion(
            hitTestBehavior: HitTestBehavior.translucent,
            onEnter: (_) => _activity(),
            onHover: (_) => _activity(),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _activity(),
              onPointerMove: (_) => _activity(),
              onPointerHover: (_) => _activity(),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AnimatedOpacity(
                  key: const ValueKey('publish-opacity'),
                  duration: const Duration(milliseconds: 150),
                  opacity: _faded ? .5 : 1,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const ValueKey('publish-background'),
                            decoration: ShapeDecoration(
                              color: t.card,
                              shape: StadiumBorder(
                                side: BorderSide(color: t.border),
                              ),
                              shadows: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            button(camera: false, live: active),
                            if (widget
                                    .session
                                    .publishCapabilities!
                                    .cameraInjection &&
                                widget.session.publishCameraAvailable.value)
                              button(camera: true, live: video),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
