// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'sample_credentials.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StreamCredentials? credentials;
  String? error;
  try {
    final dir = await getApplicationSupportDirectory();
    credentials = await consumeCredentials(File('${dir.path}/sample.json'));
  } catch (_) {
    error = 'Could not load credentials. Enter both fields.';
  }
  runApp(ExampleApp(credentials: credentials, error: error));
}

enum SampleTheme {
  light('Light'),
  dark('Dark'),
  brand('Brand');

  const SampleTheme(this.label);
  final String label;
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, this.credentials, this.error});
  final StreamCredentials? credentials;
  final String? error;
  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  SampleTheme _theme = SampleTheme.light;
  @override
  Widget build(BuildContext context) {
    final tokens = _theme == SampleTheme.dark
        ? StreamTokens.dark
        : _theme == SampleTheme.brand
        ? const StreamTokens().copyWith(
            primary: const Color(0xff005b50),
            radius: 12,
          )
        : const StreamTokens();
    return MaterialApp(
      title: 'Mobilerun sample',
      theme: ThemeData(
        brightness: _theme == SampleTheme.dark
            ? Brightness.dark
            : Brightness.light,
        colorSchemeSeed: const Color(0xff005b50),
        useMaterial3: true,
      ),
      home: StreamTheme(
        tokens: tokens,
        child: StreamPage(
          credentials: widget.credentials,
          error: widget.error,
          theme: _theme,
          onTheme: (value) => setState(() => _theme = value),
        ),
      ),
    );
  }
}

class StreamPage extends StatefulWidget {
  const StreamPage({
    super.key,
    this.credentials,
    this.error,
    required this.theme,
    required this.onTheme,
  });
  final StreamCredentials? credentials;
  final String? error;
  final SampleTheme theme;
  final ValueChanged<SampleTheme> onTheme;
  @override
  State<StreamPage> createState() => _StreamPageState();
}

class _StreamPageState extends State<StreamPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _view = DeviceStreamController();
  DeviceStreamSession? _session;
  bool _stats = false;
  bool _form = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.error;
    final credentials = widget.credentials;
    if (credentials != null) {
      _url.text = credentials.url;
      _token.text = credentials.token ?? '';
      _connect();
    }
  }

  void _connect() {
    final url = _url.text.trim();
    final token = _token.text.trim();
    if (url.isEmpty || token.isEmpty) {
      setState(() => _error = 'Enter both stream URL and token.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(_session?.close());
    setState(() {
      _error = null;
      _form = false;
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
    final brand = widget.theme == SampleTheme.brand;
    return Scaffold(
      appBar: AppBar(title: const Text('Mobilerun sample')),
      body: SafeArea(
        child: Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .5,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final mode in SampleTheme.values)
                          ChoiceChip(
                            label: Text(mode.label),
                            selected: widget.theme == mode,
                            onSelected: (_) => widget.onTheme(mode),
                          ),
                        TextButton(
                          onPressed: () => setState(() => _form = !_form),
                          child: const Text('Credentials'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _stats = !_stats),
                          child: Text(_stats ? 'Hide stats' : 'Stats'),
                        ),
                        TextButton(
                          onPressed: session == null ? null : _connect,
                          child: const Text('Reconnect'),
                        ),
                        IconButton(
                          onPressed: session == null
                              ? null
                              : _view.showKeyboard,
                          tooltip: 'Keyboard',
                          icon: const Icon(Icons.keyboard),
                        ),
                      ],
                    ),
                    if (_form) ...[
                      TextField(
                        controller: _url,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Stream URL',
                        ),
                      ),
                      TextField(
                        controller: _token,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        enableIMEPersonalizedLearning: false,
                        decoration: const InputDecoration(
                          labelText: 'Stream token',
                        ),
                      ),
                      FilledButton(
                        onPressed: _connect,
                        child: const Text('Connect'),
                      ),
                    ],
                    if (_error != null) Text(_error!),
                    if (_stats && session != null)
                      ValueListenableBuilder<StreamStats?>(
                        valueListenable: session.stats,
                        builder: (_, stats, _) {
                          String n(double? value) =>
                              value?.toStringAsFixed(1) ?? '—';
                          return Text(
                            'FPS ${n(stats?.fps)} · kbit/s ${n(stats?.bitrateKbps)} · RTT ${n(stats?.rttMs)} ms\n'
                            'Jitter buffer ${n(stats?.jitterBufferDelayMs)} ms · ICE ${stats?.localCandidateType ?? '—'}/${stats?.remoteCandidateType ?? '—'}\n'
                            'First frame ${n(stats?.timeToFirstFrameMs)} ms',
                          );
                        },
                      ),
                    DemoApproval(brand: brand),
                  ],
                ),
              ),
            ),
            Expanded(
              key: ObjectKey(session),
              child: session == null
                  ? const Center(
                      child: Text('Connect to a device, or try Demo approval.'),
                    )
                  : DeviceStream(
                      session: session,
                      controller: _view,
                      autofocus: true,
                      labels: brand
                          ? const StreamLabels(
                              back: 'Go back',
                              home: 'Start',
                              recent: 'Apps',
                            )
                          : const StreamLabels(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Local-only backend callbacks demonstrate the real approval controller/card.
class DemoApproval extends StatefulWidget {
  const DemoApproval({super.key, this.brand = false});
  final bool brand;
  @override
  State<DemoApproval> createState() => _DemoApprovalState();
}

class _DemoApprovalState extends State<DemoApproval> {
  TaskApprovalController? _controller;
  PendingApproval? _pending;
  String _last = '';
  int _fetches = 0;

  void _start() {
    _controller?.dispose();
    _pending = PendingApproval(
      approvalId: 'demo',
      kind: 'payment_card',
      details: const {'label': 'Visa 4242', 'targetPackage': 'com.shop'},
      expiresAt: DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 30))
          .toIso8601String(),
    );
    _last = '';
    _fetches = 0;
    setState(() {
      _controller = TaskApprovalController(
        taskId: 'local-demo',
        subscribe: (_, _) => () {},
        fetchApproval: (_) async {
          _fetches++;
          return _pending;
        },
        decide: (request) async {
          _last = request.decision.name;
          _pending = null;
        },
      );
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      OutlinedButton(onPressed: _start, child: const Text('Demo approval')),
      if (_controller case final controller?)
        ListenableBuilder(
          listenable: controller,
          builder: (_, _) => Column(
            children: [
              TaskApprovalCard(
                approval: controller.state.approval,
                isPending: controller.state.isDeciding,
                decision: controller.state.decision,
                onDecide: (value) => unawaited(controller.decide(value)),
                labels: widget.brand
                    ? const TaskApprovalLabels(
                        approve: 'Allow',
                        deny: 'Decline',
                      )
                    : const TaskApprovalLabels(),
              ),
              if (_last.isNotEmpty)
                Text('Decision: $_last; refetches: ${_fetches - 1}'),
            ],
          ),
        ),
    ],
  );
}
