// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Diagnostic entry point; credentials are read from private app storage at runtime.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/device_stream_session.dart';
import 'package:mobilerun_flutter/src/core/input/input_geometry.dart';
import 'package:path_provider/path_provider.dart';

import 'debug_signalling.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WebRTC.initialize(options: {'zeroPlayoutDelay': true});
  final dir = await getApplicationSupportDirectory();
  final json =
      jsonDecode(await File('${dir.path}/e2e.json').readAsString()) as Map;
  runApp(
    BenchmarkApp(
      credentials: StreamCredentials(
        url: json['streamUrl']! as String,
        token: json['streamToken']! as String,
      ),
      directory: dir,
    ),
  );
}

class BenchmarkApp extends StatefulWidget {
  const BenchmarkApp({
    super.key,
    required this.credentials,
    required this.directory,
  });
  final StreamCredentials credentials;
  final Directory directory;
  @override
  State<BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<BenchmarkApp> {
  final _capture = GlobalKey();
  final _controller = DeviceStreamController();
  DeviceStreamSession? _session;
  DebugTransports? _debug;
  TaskApprovalController? _approvals;
  bool _showApproval = false;
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
  void check(bool ok, String message) {
    if (!ok) throw StateError(message);
  }

  void log(String message) => debugPrint('BENCH $message');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(
        _run().catchError((Object e) {
          // Never print a transport exception: it can carry credentials in its URL.
          log('FAILED ${e is StateError ? e.message : e.runtimeType}');
        }),
      ),
    );
  }

  Future<void> until(
    bool Function() condition,
    String what, {
    int seconds = 60,
  }) async {
    final clock = Stopwatch()..start();
    while (!condition()) {
      final status = _debug?.signalling.rejectedStatus;
      if (status == 401 || status == 404) {
        throw StateError('device HTTP $status');
      }
      check(clock.elapsed.inSeconds < seconds, 'timeout $what');
      await wait(50);
    }
  }

  Future<void> host(String action) async {
    final ack = File('${widget.directory.path}/benchmark-ack');
    if (await ack.exists()) await ack.delete();
    log('HOST $action');
    await until(() => ack.existsSync(), 'host $action', seconds: 45);
    await ack.delete();
  }

  RenderBox get viewBox {
    RenderBox? found;
    void visit(Element element) {
      if (element.widget is DeviceStreamView) {
        found = element.findRenderObject() as RenderBox?;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found!;
  }

  (InputGeometry, RenderBox) get geometry {
    final box = viewBox, size = _session!.videoSize.value!;
    return (InputGeometry(box.size, size.width, size.height), box);
  }

  void tap(Offset point) {
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(
      PointerDownEvent(pointer: 902, position: point, buttons: 1),
    );
    binding.handlePointerEvent(PointerUpEvent(pointer: 902, position: point));
  }

  Future<void> tapLabel(String text) async {
    RenderBox? box;
    void visit(Element e) {
      if (e.widget case Text(:final data) when data == text) {
        box = e.findRenderObject() as RenderBox?;
      }
      if (e.widget case Icon(:final semanticLabel) when semanticLabel == text) {
        box = e.findRenderObject() as RenderBox?;
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    check(box != null, 'missing $text action');
    tap(box!.localToGlobal(box!.size.center(Offset.zero)));
    await wait(300);
  }

  // GPU snapshot of the rendered texture, cropped to the central 70% of the
  // upright video. Excludes status bar, toolbar and letterbox; no getStats,
  // device screenshot or outgoing packet is treated as a pixel response.
  Future<Uint8List> pixels() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    const scale = .25;
    final image = await boundary.toImage(pixelRatio: scale);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final (g, box) = geometry;
      final origin =
          box.localToGlobal(g.rect.topLeft) -
          boundary.localToGlobal(Offset.zero);
      final region = Rect.fromLTWH(
        origin.dx + g.rect.width * .15,
        origin.dy + g.rect.height * .15,
        g.rect.width * .7,
        g.rect.height * .7,
      );
      final output = BytesBuilder();
      for (
        var y = (region.top * scale).ceil();
        y < (region.bottom * scale).floor();
        y++
      ) {
        for (
          var x = (region.left * scale).ceil();
          x < (region.right * scale).floor();
          x++
        ) {
          final offset = (y * image.width + x) * 4;
          output.add(bytes.buffer.asUint8List(offset, 3));
        }
      }
      return output.takeBytes();
    } finally {
      image.dispose();
    }
  }

  double difference(Uint8List a, Uint8List b) {
    check(a.length == b.length && a.isNotEmpty, 'pixel geometry changed');
    var changed = 0;
    for (var i = 0; i < a.length; i += 3) {
      if ((a[i] - b[i]).abs() +
              (a[i + 1] - b[i + 1]).abs() +
              (a[i + 2] - b[i + 2]).abs() >
          60) {
        changed++;
      }
    }
    return changed / (a.length / 3);
  }

  double percentile(List<double> values, double p) {
    final sorted = [...values]..sort();
    return sorted[((sorted.length * p).ceil() - 1).clamp(0, sorted.length - 1)];
  }

  String number(double? value) => value?.toStringAsFixed(1) ?? 'n/a';

  Future<void> _run() async {
    await widget.directory.create(recursive: true);
    final rows = <String>[];
    for (var run = 1; run <= 5; run++) {
      final debug = DebugTransports();
      final session = createDeviceStreamSessionWithTransports(
        credentials: () async => widget.credentials,
        transports: debug.transports,
      );
      session.status.addListener(() => log('STATUS ${session.status.value}'));
      setState(() {
        _session = session;
        _debug = debug;
      });
      await WidgetsBinding.instance.endOfFrame;
      session.start();
      await until(
        () =>
            session.status.value is StreamConnected &&
            session.stats.value?.timeToFirstFrameMs != null,
        'first frame',
      );
      final samples = <StreamStats>[];
      void sample() {
        final s = session.stats.value;
        if (s != null) samples.add(s);
      }

      session.stats.addListener(sample);
      await wait(7000);
      session.stats.removeListener(sample);
      check(samples.length >= 4, 'insufficient steady samples');
      final latency = <double>[];
      for (var i = 0; i < 10; i++) {
        _controller.sendSystemKey(DeviceSystemKey.home);
        await wait(1500);
        final before = await pixels();
        check(before.toSet().length > 8, 'rendered texture snapshot is blank');
        await wait(150);
        check(
          difference(before, await pixels()) < .02,
          'baseline video is not settled',
        );
        final (g, box) = geometry;
        // Existing input fixture's Settings launcher icon on the test device.
        final target = box.localToGlobal(
          Offset(
            g.rect.left + g.rect.width * 73 / 488,
            g.rect.top + g.rect.height * 966 / 1080,
          ),
        );
        final clock = Stopwatch()..start();
        tap(target);
        var changed = false;
        while (clock.elapsedMilliseconds < 5000) {
          final after = await pixels();
          if (difference(before, after) >= .02) {
            changed = true;
            break;
          }
          await wait(8);
        }
        check(changed, 'tap did not change rendered pixels');
        latency.add(clock.elapsedMicroseconds / 1000);
        log('LATENCY run=$run sample=${i + 1} ms=${number(latency.last)}');
        await wait(500);
      }
      double? median(double? Function(StreamStats) field) {
        final values = samples.map(field).whereType<double>().toList();
        return values.isEmpty ? null : percentile(values, .5);
      }

      final s = session.stats.value!;
      rows.add(
        '| $run | ${number(s.timeToFirstFrameMs)} | ${number(median((s) => s.fps))} | ${number(median((s) => s.bitrateKbps))} | ${number(median((s) => s.rttMs))} | ${s.candidateType ?? 'n/a'} | ${number(percentile(latency, .5))} | ${number(percentile(latency, .9))} |',
      );
      await _writeResults(rows);
      log('RUN $run complete');
      if (run < 5) {
        await session.close();
        await wait(1000);
      }
    }
    await _hardening();
    log('DONE');
  }

  Future<void> _writeResults(List<String> rows) =>
      File('${widget.directory.path}/benchmark-results.md').writeAsString(
        '''# Stream benchmark

Five connections, seven seconds of steady stats and ten input samples per connection.
TTFF is attempt start to the first observed decoded frame (500 ms polling resolution).
Latency is a tap on the launcher's Settings icon to a change in at least 2% of
pixels in the central 70% of the rendered video, captured with a GPU snapshot
at quarter logical resolution. Baselines must be settled and nonblank.
Times include snapshot/readback overhead; they are observed upper bounds.

| Run | TTFF ms | FPS | Kbit/s | RTT ms | Local/remote | Input median ms | Input p90 ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
${rows.join('\n')}
''',
      );

  Future<void> _freshVideo(String what) async {
    final clock = Stopwatch()..start();
    int? previous;
    while (clock.elapsed.inSeconds < 60) {
      final frames = await _debug!.framesDecoded();
      if (_session!.status.value is StreamConnected &&
          frames != null &&
          previous != null &&
          frames > previous) {
        return;
      }
      previous = frames;
      await wait(500);
    }
    throw StateError('no fresh decoded video after $what');
  }

  Future<void> _hardening() async {
    final session = _session!;
    await host('shot phone-connected');
    // Focus Settings search before committing text through the default view.
    var (g, box) = geometry;
    tap(
      box.localToGlobal(
        Offset(
          g.rect.left + g.rect.width * .9,
          g.rect.top + g.rect.height * .065,
        ),
      ),
    );
    await wait(500);
    (g, box) = geometry;
    tap(
      box.localToGlobal(
        Offset(
          g.rect.left + g.rect.width * .45,
          g.rect.top + g.rect.height * .065,
        ),
      ),
    );
    await wait(500);
    _controller.showKeyboard();
    await wait(500);
    TextInput.updateEditingValue(const TextEditingValue(text: '\u200bdisplay'));
    await wait(1000);
    await host('shot phone-typed');
    _controller.hideKeyboard();
    for (final label in ['Back', 'Home', 'Recent']) {
      await tapLabel(label);
    }
    _debug!.killSocket();
    await until(
      () => session.status.value is StreamReconnecting,
      'socket close',
    );
    await host('shot phone-reconnecting');
    await until(
      () =>
          session.status.value is StreamConnected &&
          session.stats.value != null,
      'socket reconnect',
    );
    _debug!.signalling.failConnections = true;
    _debug!.killSocket();
    for (var i = 0; i < 12 && session.status.value is! StreamUnavailable; i++) {
      await wait(1500);
      if (session.status.value is! StreamUnavailable) session.wake();
    }
    await until(() => session.status.value is StreamUnavailable, 'unavailable');
    await host('shot phone-unavailable');
    await host('tablet');
    await host('shot tablet-unavailable');
    await host('phone');
    _debug!.signalling.failConnections = false;
    await tapLabel('Retry');
    await until(
      () =>
          session.status.value is StreamConnected &&
          session.stats.value != null,
      'retry',
    );
    var decided = false, fetches = 0;
    final approvals = TaskApprovalController(
      taskId: 'benchmark',
      fetchApproval: (_) async {
        fetches++;
        return decided
            ? null
            : const PendingApproval(
                approvalId: 'example',
                kind: 'payment_card',
                details: {
                  'label': 'Example card',
                  'targetPackage': 'com.example.app',
                },
                expiresAt: '2099-01-01T00:00:00Z',
              );
      },
      decide: (_) async {
        decided = true;
      },
    );
    setState(() {
      _approvals = approvals;
      _showApproval = true;
    });
    await wait(600);
    await host('shot phone-approval');
    await host('tablet');
    await host('shot tablet-approval');
    await host('phone');
    await tapLabel('Approve');
    await until(
      () => decided && fetches >= 2 && approvals.state.approval == null,
      'approval refetch',
    );
    setState(() => _showApproval = false);
    approvals.dispose();
    await host('tablet');
    await host('shot tablet-connected');
    await host('phone');
    await host('background');
    await until(
      () =>
          session.status.value is StreamConnected &&
          session.stats.value != null,
      'foreground',
    );
    await _freshVideo('foreground');
    await host('network');
    session.wake();
    await until(
      () =>
          session.status.value is StreamConnected &&
          session.stats.value != null,
      'network return',
    );
    await _freshVideo('network return');
    await host('shot phone-network-recovered');
    await host('soak-start');
    final startMemory = ProcessInfo.currentRss;
    final soak = Stopwatch()..start();
    var interruptions = 0, longestRecoveryMs = 0, nextProgress = 60;
    while (soak.elapsed < const Duration(minutes: 10)) {
      await wait(5000);
      if (session.status.value is! StreamConnected ||
          session.stats.value == null) {
        interruptions++;
        final recovery = Stopwatch()..start();
        log('SOAK interruption $interruptions');
        await (() async {
          await until(
            () =>
                session.status.value is StreamConnected &&
                session.stats.value != null,
            'automatic soak recovery',
          );
          await _freshVideo('automatic soak recovery');
        })().timeout(const Duration(seconds: 60));
        final elapsed = recovery.elapsedMilliseconds;
        if (elapsed > longestRecoveryMs) longestRecoveryMs = elapsed;
        log('SOAK recovered in ${elapsed}ms');
      }
      if (soak.elapsed.inSeconds >= nextProgress) {
        log('SOAK ${soak.elapsed.inSeconds}s connected');
        nextProgress += 60;
      }
    }
    await _freshVideo('soak');
    final endMemory = ProcessInfo.currentRss;
    check(
      endMemory - startMemory <= 64 * 1024 * 1024,
      'soak RSS growth exceeds 64 MiB',
    );
    await host('soak-end');
    await File('${widget.directory.path}/hardening-results.md').writeAsString(
      '# Hardening\n\nSocket rebuild, unavailable/retry, approval/refetch, navigation, text, background/foreground and network return passed.\n\n'
      'Ten-minute soak (${soak.elapsed.inSeconds}s elapsed): RSS $startMemory -> $endMemory bytes; limit 64 MiB growth.\n\n'
      'Sampled interruptions: $interruptions; longest observed recovery ${longestRecoveryMs}ms. '
      'Connection/stats checked every 5s; automatic recovery with fresh video must finish within 60s of detection.\n',
    );
    await session.close();
    check(
      session.stats.value == null &&
          session.videoSize.value == null &&
          session.videoStream.value == null,
      'closed session retained media',
    );
    await wait(2000);
    log('CLOSED media and stats cleared');
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (_session != null)
              RepaintBoundary(
                key: _capture,
                child: DeviceStream(
                  session: _session!,
                  controller: _controller,
                  autofocus: true,
                ),
              ),
            if (_showApproval && _approvals != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: ListenableBuilder(
                  listenable: _approvals!,
                  builder: (context, _) => TaskApprovalCard(
                    approval: _approvals!.state.approval,
                    onDecide: _approvals!.decide,
                    isPending: _approvals!.state.isDeciding,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
