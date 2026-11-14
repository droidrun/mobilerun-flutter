// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

/// Offline default stream chrome demo. The provider never opens a real device.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WebRTC.initialize(options: {'zeroPlayoutDelay': true});
  runApp(const MaterialApp(home: StreamGallery()));
}

/// Exercises the actual session's loading, exhausted retries and retry UI.
class StreamGallery extends StatefulWidget {
  const StreamGallery({super.key});
  @override
  State<StreamGallery> createState() => _StreamGalleryState();
}

class _StreamGalleryState extends State<StreamGallery> {
  late DeviceStreamSession _session;
  var _theme = 'Light';
  var _customSlots = false;
  var _hasControl = true;

  @override
  void initState() {
    super.initState();
    _session = _createSession(false);
  }

  DeviceStreamSession _createSession(bool fail) {
    var calls = 0;
    return DeviceStreamSession(
      credentials: () async {
        // Model a backend outage, then a booting device after manual retry.
        // Use normal retry timing; no real credentials or network are involved.
        if (fail && ++calls <= 7) {
          throw StateError('Preview backend unavailable');
        }
        return null;
      },
    )..start();
  }

  void _reset(bool fail) {
    final previous = _session;
    setState(() => _session = _createSession(fail));
    unawaited(previous.close());
  }

  @override
  void dispose() {
    unawaited(_session.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _theme == 'Dark'
        ? StreamTokens.dark
        : _theme == 'Custom'
        ? const StreamTokens().copyWith(
            background: const Color(0xfff2faf5),
            card: const Color(0xfff2faf5),
            primary: const Color(0xff005b50),
            radius: 12,
          )
        : const StreamTokens();
    final labels = _theme == 'Custom'
        ? const StreamLabels(
            connecting: 'Starting preview',
            reconnecting: 'Recovering preview',
            unavailable: 'Preview unavailable',
            retry: 'Try again',
            back: 'Return',
            home: 'Main',
            recent: 'Apps',
          )
        : const StreamLabels();
    return StreamTheme(
      tokens: tokens,
      child: Scaffold(
        backgroundColor: tokens.background,
        appBar: AppBar(title: const Text('Stream gallery')),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Connecting'),
                      onPressed: () => _reset(false),
                    ),
                    ActionChip(
                      label: const Text('Unavailable'),
                      onPressed: () => _reset(true),
                    ),
                    for (final mode in ['Light', 'Dark', 'Custom'])
                      ActionChip(
                        label: Text(mode),
                        onPressed: () => setState(() => _theme = mode),
                      ),
                    ActionChip(
                      label: const Text('Slots'),
                      onPressed: () =>
                          setState(() => _customSlots = !_customSlots),
                    ),
                    ActionChip(
                      label: const Text('Display only'),
                      onPressed: () =>
                          setState(() => _hasControl = !_hasControl),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DeviceStreamView(
                    session: _session,
                    hasControl: _hasControl,
                    labels: labels,
                    placeholderBuilder: _customSlots
                        ? _placeholder
                        : defaultStreamPlaceholder,
                    unavailableBuilder: _customSlots
                        ? _unavailable
                        : defaultStreamUnavailable,
                    navigationBuilder: _customSlots
                        ? _navigation
                        : defaultStreamNavigation,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _placeholder(BuildContext context, StreamOverlayState state) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Custom placeholder: ${state.label}',
        style: StreamTheme.of(
          context,
        ).typography.copyWith(color: StreamTheme.of(context).foreground),
      ),
      const SizedBox(height: 12),
      defaultStreamPlaceholder(context, state),
    ],
  ),
);

Widget _unavailable(BuildContext context, StreamOverlayState state) => Center(
  child: TextButton(
    onPressed: state.retry,
    child: Text('Custom retry: ${state.labels.retry}'),
  ),
);

Widget _navigation(BuildContext context, StreamNavigationState state) =>
    SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Custom navigation',
            style: StreamTheme.of(
              context,
            ).typography.copyWith(color: StreamTheme.of(context).foreground),
          ),
          IconButton(
            tooltip: state.labels.home,
            onPressed: state.canControl
                ? () => state.onAction(DeviceSystemKey.home)
                : null,
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
    );
