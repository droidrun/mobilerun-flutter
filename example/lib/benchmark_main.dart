// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

// Diagnostic entry point; credentials are read from private app storage at runtime.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

class _VideoPixels {
  const _VideoPixels(this.width, this.height, this.rgb);
  final int width, height;
  final Uint8List rgb;
}

class _BenchmarkAppState extends State<BenchmarkApp> {
  final _capture = GlobalKey();
  final _controller = DeviceStreamController();
  DeviceStreamSession? _session;
  DebugTransports? _debug;
  TaskApprovalController? _approvals;
  bool _showApproval = false;
  VoidCallback? _statsObserver;
  bool get _connected =>
      _session?.status.value is StreamConnected &&
      _session?.stats.value != null;
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

  // GPU snapshot cropped to upright video, at quarter video resolution.
  Future<_VideoPixels> pixels() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final (g, box) = geometry;
    final scale = g.videoWidth / g.rect.width * .25;
    final image = await boundary.toImage(pixelRatio: scale);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final origin =
          box.localToGlobal(g.rect.topLeft) -
          boundary.localToGlobal(Offset.zero);
      final left = (origin.dx * scale).ceil(), top = (origin.dy * scale).ceil();
      final width = (g.rect.width * scale).floor(),
          height = (g.rect.height * scale).floor();
      final output = Uint8List(width * height * 3);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final offset = ((top + y) * image.width + left + x) * 4;
          final target = (y * width + x) * 3;
          output.setRange(
            target,
            target + 3,
            bytes.buffer.asUint8List(offset, 3),
          );
        }
      }
      return _VideoPixels(width, height, output);
    } finally {
      image.dispose();
    }
  }

  // Kotlin's maximum 4x4-tile mean absolute luma difference.
  double difference(_VideoPixels a, _VideoPixels b, Rect region) {
    check(a.width == b.width && a.height == b.height, 'pixel geometry changed');
    final rect = region.intersect(
      Rect.fromLTWH(0, 0, a.width.toDouble(), a.height.toDouble()),
    );
    double luma(Uint8List rgb, int pixel) =>
        .2126 * rgb[pixel * 3] +
        .7152 * rgb[pixel * 3 + 1] +
        .0722 * rgb[pixel * 3 + 2];
    var maximum = 0.0;
    for (var y = rect.top.floor(); y < rect.bottom.ceil(); y += 4) {
      for (var x = rect.left.floor(); x < rect.right.ceil(); x += 4) {
        var total = 0.0, count = 0;
        for (var py = y; py < y + 4 && py < rect.bottom.ceil(); py++) {
          for (var px = x; px < x + 4 && px < rect.right.ceil(); px++) {
            final pixel = py * a.width + px;
            total += (luma(a.rgb, pixel) - luma(b.rgb, pixel)).abs();
            count++;
          }
        }
        final mean = total / count;
        if (mean > maximum) maximum = mean;
      }
    }
    return maximum;
  }

  double median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isEven
        ? (sorted[mid - 1] + sorted[mid]) / 2
        : sorted[mid];
  }

  double p90(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[(sorted.length * .9).ceil() - 1];
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
      final samples = <StreamStats>[];
      var collectSteady = false;
      void sample() {
        final value = session.stats.value;
        if (collectSteady &&
            value != null &&
            value.bitrateKbps != null &&
            samples.length < 10) {
          samples.add(value);
        }
      }

      _statsObserver = sample;
      session.stats.addListener(sample);
      await WidgetsBinding.instance.endOfFrame;
      session.start();
      await until(
        () => _connected && session.stats.value!.timeToFirstFrameMs != null,
        'first frame',
      );
      collectSteady = true;
      await until(
        () => samples.length == 10,
        'ten fresh steady samples',
        seconds: 20,
      );
      collectSteady = false;
      final latency = <double>[], appLaunch = <double>[];
      for (var i = 0; i < 10; i++) {
        _controller.sendSystemKey(DeviceSystemKey.home);
        await wait(1500);
        final (g, box) = geometry;
        final videoTap = Offset(
          g.videoWidth * 73 / 488,
          g.videoHeight * 966 / 1080,
        );
        final target = box.localToGlobal(
          Offset(
            g.rect.left + g.rect.width * 73 / 488,
            g.rect.top + g.rect.height * 966 / 1080,
          ),
        );
        var before = await pixels();
        check(
          before.rgb.toSet().length > 8,
          'rendered texture snapshot is blank',
        );
        final rx = 32 / g.videoWidth * before.width,
            ry = 32 / g.videoHeight * before.height;
        final cx = videoTap.dx / g.videoWidth * before.width,
            cy = videoTap.dy / g.videoHeight * before.height;
        final tapRegion = Rect.fromLTRB(
          cx - rx,
          cy - ry,
          cx + rx + 1,
          cy + ry + 1,
        );
        final launchRegion = Rect.fromLTRB(
          before.width * .2,
          before.height * .2,
          before.width * .8,
          before.height * .6,
        );
        final settle = Stopwatch()..start();
        var stable = 0;
        while (stable < 4) {
          check(
            settle.elapsedMilliseconds < 10000,
            'tap baseline is not settled',
          );
          await wait(100);
          final next = await pixels();
          stable = difference(before, next, tapRegion) < 1 ? stable + 1 : 0;
          before = next;
        }
        final clock = Stopwatch()..start();
        tap(target);
        double? tapMs, launchMs;
        while (clock.elapsedMilliseconds < 10000 &&
            (tapMs == null || launchMs == null)) {
          final after = await pixels();
          final elapsed = clock.elapsedMicroseconds / 1000;
          if (difference(before, after, tapRegion) >= 4) tapMs ??= elapsed;
          if (difference(before, after, launchRegion) >= 4) {
            launchMs ??= elapsed;
          }
          await wait(8);
        }
        check(
          tapMs != null && launchMs != null,
          'tap/app launch did not change rendered pixels',
        );
        latency.add(tapMs!);
        appLaunch.add(launchMs!);
        log(
          'LATENCY run=$run sample=${i + 1} tapMs=${number(tapMs)} appLaunchMs=${number(launchMs)}',
        );
        await wait(500);
      }
      double? mean(double? Function(StreamStats) field) {
        final values = samples.map(field).whereType<double>().toList();
        return values.isEmpty
            ? null
            : values.reduce((a, b) => a + b) / values.length;
      }

      final last = samples.last;
      final candidates =
          last.localCandidateType == null || last.remoteCandidateType == null
          ? 'n/a'
          : '${last.localCandidateType}/${last.remoteCandidateType}';
      rows.add(
        '| $run | ${number(last.timeToFirstFrameMs)} | ${number(mean((s) => s.fps))} | ${number(mean((s) => s.bitrateKbps))} | ${number(mean((s) => s.rttMs))} | $candidates | ${number(median(latency))} | ${number(p90(latency))} | ${number(median(appLaunch))} | ${number(p90(appLaunch))} |',
      );
      await _writeResults(rows);
      log('RUN $run complete');
      if (run < 5) {
        await session.close();
        session.stats.removeListener(sample);
        await wait(1000);
      }
    }
    await _hardening();
    log('DONE');
  }

  Future<void> _writeResults(List<String> rows) =>
      File('${widget.directory.path}/benchmark-results.md').writeAsString(
        '''# Stream benchmark

Five connections; arithmetic means of ten fresh one-second steady stats samples each.
TTFF is attempt start to the first observed decoded frame (50 ms polling interval).
Tap latency uses a ~64x64 upright-video-pixel region around the input point.
App launch uses a separate central region (20–80% width, 20–60% height).
Both use maximum 4x4-tile mean absolute luma difference >=4, after four
stable tap-region snapshots (<1 difference). GPU snapshots use quarter video resolution.
Times include GPU snapshot/readback overhead and are observed upper bounds.
Medians average the middle two of ten samples; p90 uses nearest rank.

| Run | TTFF ms | Mean FPS | Mean Kbit/s | Mean RTT ms | Local/remote | Tap median ms | Tap p90 ms | App launch median ms | App launch p90 ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
${rows.join('\n')}
''',
      );

  Future<void> _freshVideo(String what) async {
    final clock = Stopwatch()..start();
    int? previous;
    while (clock.elapsed.inSeconds < 60) {
      final frames = await _debug!.framesDecoded();
      if (_connected &&
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
    await until(() => _connected, 'socket reconnect');
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
    await until(() => _connected, 'retry');
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
    await until(() => _connected, 'foreground');
    await _freshVideo('foreground');
    await host('network');
    session.wake();
    await until(() => _connected, 'network return');
    await _freshVideo('network return');
    await host('shot phone-network-recovered');
    await host('soak-start');
    final startMemory = ProcessInfo.currentRss;
    final soak = Stopwatch()..start();
    var interruptions = 0, longestRecoveryMs = 0, nextProgress = 60;
    while (soak.elapsed < const Duration(minutes: 10)) {
      await wait(5000);
      if (!_connected) {
        interruptions++;
        final recovery = Stopwatch()..start();
        log('SOAK interruption $interruptions');
        await (() async {
          await until(() => _connected, 'automatic soak recovery');
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
    session.stats.removeListener(_statsObserver!);
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
