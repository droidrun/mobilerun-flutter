// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

/// Shows the status line and the video of a [DeviceStreamSession].
class StreamView extends StatefulWidget {
  const StreamView({super.key, required this.session, this.log});

  final DeviceStreamSession session;

  /// Receives renderer events, for the scripted run.
  final void Function(String message)? log;

  @override
  State<StreamView> createState() => _StreamViewState();
}

class _StreamViewState extends State<StreamView> {
  final _renderer = RTCVideoRenderer();
  bool _ready = false;

  // The video stream is internal until the SDK ships its own widget.
  // ignore: invalid_use_of_internal_member
  ValueListenable<MediaStream?> get _stream => widget.session.videoStream;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    await _renderer.initialize();
    if (!mounted) return;
    _renderer
      ..onFirstFrameRendered = () => widget.log?.call('renderer first frame')
      ..onResize = () => widget.log?.call(
        'renderer size ${_renderer.videoWidth}x${_renderer.videoHeight}',
      );
    _stream.addListener(_sync);
    _sync();
    setState(() => _ready = true);
  }

  void _sync() {
    final stream = _stream.value;
    widget.log?.call('renderer srcObject set=${stream != null}');
    _renderer.srcObject = stream;
  }

  @override
  void dispose() {
    _stream.removeListener(_sync);
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Column(
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([session.status, session.videoSize]),
          builder: (context, _) {
            final size = session.videoSize.value;
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                [
                  '${session.status.value}',
                  if (size != null) '${size.width}x${size.height}',
                ].join('  '),
                key: const Key('status'),
              ),
            );
          },
        ),
        Expanded(
          child: ColoredBox(
            color: Colors.black,
            child: _ready
                ? RTCVideoView(
                    _renderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
