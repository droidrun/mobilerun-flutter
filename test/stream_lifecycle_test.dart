// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/device_stream_session.dart'
    show createDeviceStreamSessionWithTransports;
import 'package:mobilerun_flutter/src/core/stream_transports.dart';

import 'support/fake_scheduler.dart';
import 'support/fake_transports.dart';

void main() {
  testWidgets('connectivity source replacement retains offline state', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final scheduler = FakeScheduler();
    final connector = FakeConnector(scheduler)
      ..failWith = StateError('offline');
    final session = createDeviceStreamSessionWithTransports(
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
      final session = createDeviceStreamSessionWithTransports(
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
      final unfocusedAdapter = StreamLifecycle(session: session);
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
      expect(fetches, 2);
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
    final session = createDeviceStreamSessionWithTransports(
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
      final session = createDeviceStreamSessionWithTransports(
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
