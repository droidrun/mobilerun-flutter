// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'debug_signalling.dart';
import 'e2e_script.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mobilerun stream example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const StreamPage(),
  );
}

class StreamPage extends StatefulWidget {
  const StreamPage({super.key});

  @override
  State<StreamPage> createState() => _StreamPageState();
}

class _StreamPageState extends State<StreamPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _renderer = RTCVideoRenderer();
  final _signalling = DebugSignalling();
  DeviceStreamSession? _session;
  bool _rendererReady = false;
  String _script = '';

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    await _renderer.initialize();
    _renderer
      ..onFirstFrameRendered = () => debugPrint('E2E renderer first frame')
        ..onResize = () => debugPrint(
          'E2E renderer size ${_renderer.videoWidth}x${_renderer.videoHeight}',
        );
    if (!mounted) return;
    setState(() => _rendererReady = true);
    final config = await E2eConfig.load();
    if (config != null && mounted) unawaited(_runScript(config));
  }

  DeviceStreamSession _newSession(String url, String token) {
    final session = DeviceStreamSession.withTransports(
      credentials: () async => StreamCredentials(url: url, token: token),
      transports: StreamTransports(
        signalling: _signalling,
        peers: defaultStreamTransports().peers,
      ),
    );
    session.videoStream.addListener(() {
      final stream = session.videoStream.value;
      debugPrint('E2E renderer srcObject set=${stream != null}');
      _renderer.srcObject = stream;
    });
    return session;
  }

  Future<void> _runScript(E2eConfig config) async {
    final session = _session = _newSession(config.url, config.token);
    setState(() {});
    // The host script screenshots the emulator when it sees the marker.
    final script = E2eScript(
      session: session,
      signalling: _signalling,
      hostShot: (name) async {
        debugPrint('E2E SHOT $name');
        await Future<void>.delayed(const Duration(seconds: 2));
      },
    );
    try {
      await script.run();
      if (mounted) setState(() => _script = 'done');
    } on Object catch (error) {
      debugPrint('E2E FAILED ${error.runtimeType}: $error');
      if (mounted) setState(() => _script = 'failed');
    }
  }

  void _connect() {
    unawaited(_session?.close());
    final session = _session = _newSession(_url.text.trim(), _token.text.trim())
      ..start();
    setState(() => _script = '');
    session.status.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    unawaited(_session?.close());
    _renderer.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Mobilerun stream example')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  TextField(
                    controller: _url,
                    decoration: const InputDecoration(labelText: 'Stream URL'),
                  ),
                  TextField(
                    controller: _token,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Token'),
                  ),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _connect,
                        child: const Text('Connect'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: session?.retry,
                        child: const Text('Retry'),
                      ),
                      const SizedBox(width: 16),
                      if (session != null)
                        ValueListenableBuilder(
                          valueListenable: session.status,
                          builder: (_, status, _) => Text(
                            [
                              '$status',
                              if (session.videoSize.value != null)
                                '${session.videoSize.value!.width}x${session.videoSize.value!.height}',
                              if (_script.isNotEmpty) 'script $_script',
                            ].join('  '),
                            key: const Key('status'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: _rendererReady
                    ? RTCVideoView(_renderer)
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
