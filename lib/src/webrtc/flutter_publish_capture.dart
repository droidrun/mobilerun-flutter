// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/publish.dart';
import '../core/publish_transport.dart';
import '../core/stream_error.dart';

/// Capture through the existing plugin's permission facilities.
final class FlutterPublishCapture implements PublishCapture {
  /// Creates a capture adapter without opening inputs or prompting.
  const FlutterPublishCapture();

  @override
  Future<PublishMedia> capture(
    PublishOptions options, {
    required bool Function() isCancelled,
    required void Function(PublishMedia media) onAcquired,
  }) async {
    final media = _CapturedMedia();
    onAcquired(media);
    try {
      // Acquire separately so camera refusal cannot hide an already-open mic
      // inside a failed plugin call. The entire request still succeeds atomically.
      await media.add(
        await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        }),
      );
      if (isCancelled()) {
        await media.stop();
        return media;
      }
      if (options.video) {
        await media.add(
          await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': {
              'width': {'ideal': 1280, 'max': 1280},
              'height': {'ideal': 720, 'max': 720},
              'frameRate': {'ideal': 24, 'max': 30},
            },
          }),
        );
      }
      if (isCancelled()) {
        await media.stop();
        return media;
      }
      final kinds = media.tracks.map((track) => track.kind).toList();
      if (!kinds.contains('audio') ||
          (options.video && !kinds.contains('video'))) {
        throw StateError('Missing capture track');
      }
      return media;
    } on Object catch (error) {
      await media.stop();
      // flutter_webrtc 1.6.3 flattens PlatformException to a string. Its
      // Android/iOS permission paths both emit DOMException / NotAllowedError.
      // Do not expose the original platform message to error observers.
      final denied = RegExp(r'\b(NotAllowedError|SecurityError)\b')
          .hasMatch(error.toString());
      throw PublishException(
        PublishFailure(
          reason: denied
              ? StreamErrorReason.permissionDenied
              : StreamErrorReason.publishFailed,
          message: denied
              ? 'Microphone or camera permission denied'
              : 'Local input unavailable',
          detail: denied ? 'capture_permission' : 'capture_unavailable',
        ),
      );
    }
  }
}

final class _CapturedMedia implements PublishMedia {
  final streams = <MediaStream>[];
  Future<void>? _stopping;

  Future<void> add(MediaStream stream) async {
    if (_stopping == null) {
      streams.add(stream);
      return;
    }
    // Cancellation may finish while a platform permission prompt is still open.
    // Every stream returned after it is released immediately, including camera.
    await _releaseStream(stream);
  }

  static Future<void> _releaseStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      track.onEnded = null;
      try {
        await track.stop();
      } on Object {
        /* Release remaining inputs. */
      }
    }
    try {
      await stream.dispose();
    } on Object {
      /* Already released. */
    }
  }

  @override
  List<MediaStreamTrack> get tracks => [
    for (final stream in streams) ...stream.getTracks(),
  ];

  @override
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    for (final stream in streams) {
      await _releaseStream(stream);
    }
  }
}
