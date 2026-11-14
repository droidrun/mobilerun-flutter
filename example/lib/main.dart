// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WebRTC.initialize(options: {'zeroPlayoutDelay': true});
  runApp(const ExampleApp());
}

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
  DeviceStreamSession? _session;
  final _view = DeviceStreamController();

  void _connect() {
    unawaited(_session?.close());
    final url = _url.text.trim();
    final token = _token.text.trim();
    setState(() {
      _session = DeviceStreamSession(
        credentials: () async => StreamCredentials(url: url, token: token),
      )..start();
    });
  }

  @override
  void dispose() {
    unawaited(_session?.close());
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
                      IconButton(
                        onPressed: session == null ? null : _view.showKeyboard,
                        tooltip: 'Keyboard',
                        icon: const Icon(Icons.keyboard),
                      ),
                      OutlinedButton(
                        onPressed: session?.retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (session != null)
              Expanded(
                key: ObjectKey(session),
                child: DeviceStream(
                  session: session,
                  controller: _view,
                  autofocus: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
