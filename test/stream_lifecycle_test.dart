// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

// Use the plugin's official observation boundary without another dependency.
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/stream_transports.dart';

import 'support/fake_scheduler.dart';
import 'support/fake_transports.dart';
import 'support/harness.dart' show Harness, pump;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late ConnectivityPlatform originalPlatform;
  late _Connectivity platform;
  setUp(() {
    originalPlatform = ConnectivityPlatform.instance;
    platform = _Connectivity();
    ConnectivityPlatform.instance = platform;
  });
  tearDown(() async {
    ConnectivityPlatform.instance = originalPlatform;
    await platform.changes.close();
  });

  test(
    'default source observes initial offline and normalizes transport lists',
    () async {
      final h = Harness();
      final adapter = StreamLifecycle(session: h.session);
      await pump();
      h.session.start();
      await pump();
      expect(platform.checks, 1);
      expect(platform.changes.hasListener, isTrue);
      expect(h.credentialCalls, 0);
      expect(h.connector.uris, isEmpty);
      platform.changes.add([ConnectivityResult.none, ConnectivityResult.wifi]);
      platform.changes.add([ConnectivityResult.wifi]);
      await pump();
      expect(h.connector.uris, hasLength(1));
      adapter.dispose();
      await h.session.close();
    },
  );

  test('supplied source replaces default and null restores it', () async {
    final h = Harness();
    final custom = StreamController<bool>.broadcast(sync: true);
    final adapter = StreamLifecycle(
      session: h.session,
      connectivity: custom.stream,
    );
    custom.add(false);
    h.session.start();
    await pump();
    expect(platform.checks, 0);
    expect(platform.changes.hasListener, isFalse);
    expect(h.credentialCalls, 0);
    adapter.updateConnectivity(null);
    await pump();
    expect(platform.checks, 1);
    expect(platform.changes.hasListener, isTrue);
    custom.add(true);
    await pump();
    expect(h.credentialCalls, 0);
    platform.changes.add([ConnectivityResult.mobile]);
    await pump();
    expect(h.connector.uris, hasLength(1));
    adapter.dispose();
    await h.session.close();
    await custom.close();
  });

  test('newer event wins over stale initial check', () async {
    final h = Harness();
    final snapshot = Completer<List<ConnectivityResult>>();
    platform.snapshot = snapshot.future;
    final adapter = StreamLifecycle(session: h.session);
    platform.changes.add([ConnectivityResult.none]);
    snapshot.complete([ConnectivityResult.wifi]);
    await pump();
    h.session.start();
    await pump();
    expect(h.credentialCalls, 0);
    expect(h.connector.uris, isEmpty);
    adapter.dispose();
    await h.session.close();
  });

  test('source replacement invalidates pending default check', () async {
    final h = Harness();
    final snapshot = Completer<List<ConnectivityResult>>();
    platform.snapshot = snapshot.future;
    final adapter = StreamLifecycle(session: h.session);
    final custom = StreamController<bool>.broadcast(sync: true);
    adapter.updateConnectivity(custom.stream);
    custom.add(false);
    snapshot.complete([ConnectivityResult.wifi]);
    await pump();
    h.session.start();
    await pump();
    expect(h.credentialCalls, 0);
    expect(h.connector.uris, isEmpty);
    adapter.dispose();
    await h.session.close();
    await custom.close();
  });

  test(
    'resume refreshes default snapshot and disposed adapter stays silent',
    () async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = Harness();
      final adapter = StreamLifecycle(session: h.session);
      await pump();
      h.session.start();
      await pump();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final snapshot = Completer<List<ConnectivityResult>>();
      platform.snapshot = snapshot.future;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pump();
      expect(platform.checks, 2);
      expect(h.credentialCalls, 0);
      adapter.dispose();
      snapshot.complete([ConnectivityResult.wifi]);
      platform.changes.add([ConnectivityResult.wifi]);
      await pump();
      expect(h.credentialCalls, 0);
      expect(h.connector.uris, isEmpty);
      // Detaching the adapter leaves the owner responsible for availability.
      h.session.setNetworkAvailable(true);
      await pump();
      expect(h.connector.uris, hasLength(1));
      await h.session.close();
    },
  );

  test(
    'resume snapshot recovers from initial offline without a platform event',
    () async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final h = Harness();
      final adapter = StreamLifecycle(session: h.session);
      await pump();
      h.session.start();
      await pump();
      expect(h.credentialCalls, 0);
      expect(h.connector.uris, isEmpty);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      platform.snapshot = Future.value([ConnectivityResult.wifi]);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pump();
      expect(platform.checks, 2);
      expect(h.connector.uris, hasLength(1));
      adapter.dispose();
      await h.session.close();
    },
  );

  test('plugin errors stay unknown without retry polling', () async {
    final h = Harness();
    platform.snapshot = Future.error(StateError('plugin unavailable'));
    final adapter = StreamLifecycle(session: h.session);
    platform.changes.addError(StateError('plugin unavailable'));
    await pump();
    h.session.start();
    await pump();
    expect(platform.checks, 1);
    expect(h.connector.uris, hasLength(1));
    expect(h.errors, isEmpty);
    adapter.dispose();
    await h.session.close();
  });

  testWidgets('connectivity source replacement retains offline state', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final scheduler = FakeScheduler();
    final connector = FakeConnector(scheduler)
      ..failWith = StateError('offline');
    final session = DeviceStreamSession.withTransports(
      credentials: () async =>
          const StreamCredentials(url: 'wss://example.test/s', token: 'test'),
      transports: StreamTransports(
        signalling: connector,
        peers: FakePeerFactory('offer'),
      ),
      scheduler: scheduler,
    );
    session.start();
    await tester.pump();
    final first = StreamController<bool>.broadcast(sync: true);
    final second = StreamController<bool>.broadcast(sync: true);
    final adapter = StreamLifecycle(
      session: session,
      connectivity: first.stream,
    );
    first.add(false);
    final before = connector.uris.length;
    adapter.updateConnectivity(second.stream);
    first.add(true); // Detached source must not wake.
    await tester.pump();
    expect(connector.uris.length, before);
    second.add(
      true,
    ); // Known offline -> online, even across source replacement.
    await tester.pump();
    expect(connector.uris.length, before + 1);
    second.add(true);
    await tester.pump();
    expect(connector.uris.length, before + 1);
    adapter.dispose();
    await session.close();
    await first.close();
    await second.close();
    expect(scheduler.pendingTimers, 0);
  });

  testWidgets(
    'initial foreground/online and repeated snapshots do not wake; real transitions do',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final scheduler = FakeScheduler();
      final connector = FakeConnector(scheduler)
        ..failWith = StateError('offline');
      var fetches = 0;
      final session = DeviceStreamSession.withTransports(
        credentials: () async {
          fetches++;
          return const StreamCredentials(
            url: 'wss://example.test/stream',
            token: 'test',
          );
        },
        transports: StreamTransports(
          signalling: connector,
          peers: FakePeerFactory('offer'),
        ),
        scheduler: scheduler,
        random: () => .5,
      );
      session.start();
      await tester.pump();
      expect(session.status.value, isA<StreamReconnecting>());
      final before = connector.uris.length;
      final network = StreamController<bool>.broadcast(sync: true);
      final adapter = StreamLifecycle(
        session: session,
        connectivity: network.stream,
      );
      addTearDown(adapter.dispose);
      network.add(true);
      network.add(true);
      await tester.pump();
      expect(connector.uris.length, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(connector.uris.length, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final unfocusedAdapter = StreamLifecycle(
        session: session,
        connectivity: const Stream.empty(),
      );
      addTearDown(unfocusedAdapter.dispose);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(connector.uris.length, before);
      unfocusedAdapter.dispose();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(connector.uris.length, before + 1);
      network.add(false);
      network.add(true);
      await tester.pump();
      expect(connector.uris.length, before + 2);
      network.add(true);
      await tester.pump();
      expect(connector.uris.length, before + 2);
      adapter.dispose();
      network.add(false);
      network.add(true);
      await tester.pump();
      expect(connector.uris.length, before + 2);
      expect(fetches, 3);
      await session.close();
      await network.close();
      expect(scheduler.pendingTimers, 0);
    },
  );

  test('hidden session suppresses keepAlive; foreground resumes', () async {
    Future<void> flush() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final scheduler = FakeScheduler();
    final connector = FakeConnector(scheduler);
    final peers = FakePeerFactory('offer');
    final session = DeviceStreamSession.withTransports(
      credentials: () async => const StreamCredentials(
        url: 'wss://example.test/stream',
        token: 'test',
      ),
      transports: StreamTransports(signalling: connector, peers: peers),
      scheduler: scheduler,
    );
    session.start();
    await flush();
    connector.last.receive({
      'type': 'rtcConfiguration',
      'rtcConfiguration': {'iceServers': []},
    });
    await flush();
    peers.last.emitState(PeerState.connected);
    await flush();
    scheduler.advanceTo(10000);
    await flush();
    expect(connector.last.ofType('keepAlive').map((f) => f.atMs), [10000]);
    session.setVisible(false);
    scheduler.advanceTo(40000);
    await flush();
    expect(connector.last.ofType('keepAlive').map((f) => f.atMs), [10000]);
    session.setVisible(true);
    scheduler.advanceTo(50000);
    await flush();
    expect(connector.last.ofType('keepAlive').map((f) => f.atMs), [
      10000,
      50000,
    ]);
    await session.close();
    expect(scheduler.pendingTimers, 0);
  });

  testWidgets(
    'null credentials remain connecting past watchdog, and close cancels polling',
    (tester) async {
      final scheduler = FakeScheduler();
      final connector = FakeConnector(scheduler);
      var calls = 0;
      final session = DeviceStreamSession.withTransports(
        credentials: () async {
          calls++;
          return null;
        },
        transports: StreamTransports(
          signalling: connector,
          peers: FakePeerFactory('offer'),
        ),
        scheduler: scheduler,
      );
      session.start();
      await tester.pump();
      for (var i = 1; i <= 30; i++) {
        scheduler.advanceTo(i * 3000);
        await tester.pump();
      }
      expect(calls, 31);
      expect(session.status.value, isA<StreamConnecting>());
      expect(connector.connections, isEmpty);
      await session.close();
      expect(scheduler.pendingTimers, 0);
      scheduler.advanceTo(200000);
      await tester.pump();
      expect(calls, 31);
    },
  );
}

final class _Connectivity extends ConnectivityPlatform {
  final changes = StreamController<List<ConnectivityResult>>.broadcast(
    sync: true,
  );
  Future<List<ConnectivityResult>>? snapshot;
  int checks = 0;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => changes.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() {
    checks++;
    return snapshot ?? Future.value([ConnectivityResult.none]);
  }
}
