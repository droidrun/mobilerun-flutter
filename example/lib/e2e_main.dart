// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Entry point of the scripted emulator run (`flutter build apk -t
// lib/e2e_main.dart`, driven by tool/e2e_android.sh). It reads the stream URL
// and token at run time from a private file in the app's support directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// The scripted run needs the internal transport hook.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/device_stream_session.dart'
    show createDeviceStreamSessionWithTransports;
import 'package:path_provider/path_provider.dart';

import 'debug_signalling.dart';
import 'input_e2e_script.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WebRTC.initialize(options: {'zeroPlayoutDelay': true});
  final dir = await getApplicationSupportDirectory();
  final json =
      jsonDecode(await File('${dir.path}/e2e.json').readAsString()) as Map;
  runApp(
    E2eApp(
      credentials: StreamCredentials(
        url: json['streamUrl']! as String,
        token: json['streamToken']! as String,
      ),
      outDir: Directory('${dir.path}/e2e-out'),
    ),
  );
}

class E2eApp extends StatefulWidget {
  const E2eApp({super.key, required this.credentials, required this.outDir});

  final StreamCredentials credentials;
  final Directory outDir;

  @override
  State<E2eApp> createState() => _E2eAppState();
}

class _E2eAppState extends State<E2eApp> {
  final _debug = DebugTransports();
  final _controller = DeviceStreamController();
  final _viewKey = GlobalKey();
  bool _rotated = false;
  late final DeviceStreamSession _session =
      createDeviceStreamSessionWithTransports(
        credentials: () async => widget.credentials,
        transports: _debug.transports,
      );

  @override
  void initState() {
    super.initState();
    final script = InputE2eScript(
      controller: _controller,
      viewKey: _viewKey,
      rotateView: (value) async {
        setState(() => _rotated = value);
        await WidgetsBinding.instance.endOfFrame;
      },
      session: _session,
      debug: _debug,
      outDir: widget.outDir,
      hostShot: (name) async {
        debugPrint('E2E SHOT $name');
        await Future<void>.delayed(const Duration(seconds: 2));
      },
    );
    unawaited(
      script.run().then(
        (_) => debugPrint('E2E DONE'),
        onError: (Object error) =>
            debugPrint('E2E FAILED ${error.runtimeType}: $error'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: ColoredBox(
          color: Colors.black,
          child: RotatedBox(
            quarterTurns: _rotated ? 1 : 0,
            child: DeviceStreamView(
              key: _viewKey,
              session: _session,
              hasControl: true,
              controller: _controller,
              autofocus: true,
            ),
          ),
        ),
      ),
    ),
  );
}
