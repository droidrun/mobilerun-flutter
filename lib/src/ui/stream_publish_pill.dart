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
        );
      }

      return Material(
        color: t.card,
        shape: StadiumBorder(side: BorderSide(color: t.border)),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button(camera: false, live: active),
                  if (widget.session.publishCapabilities!.cameraInjection &&
                      widget.session.publishCameraAvailable.value)
                    button(camera: true, live: video),
                ],
              ),
              if (error != null || pending)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    error ?? labels.publishStarting,
                    textAlign: TextAlign.center,
                    style: t.typography.copyWith(
                      color: error == null ? t.mutedForeground : t.destructive,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
