// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/device_stream_session.dart'
    show createDeviceStreamSessionWithTransports;
import 'package:mobilerun_flutter/src/core/stream_transports.dart';

import 'fake_scheduler.dart';
import 'fake_transports.dart';
import 'fixtures.dart';

/// Lets pending futures and zero-delay stream events run.
Future<void> pump() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, Object?> example(String file, [int index = 0]) {
  final examples = readObjects('signalling/$file', 'examples');
  return asObject(examples[index]['json']);
}

const sessionId = 'sess_0123456789abcdef';

/// A session on fake transports and a virtual clock, with a status log.
final class Harness {
  Harness({
    StreamConfig config = const StreamConfig(),
    FutureOr<StreamCredentials?> Function(int call)? credentials,
  }) {
    connector = FakeConnector(scheduler);
    final offer = example('client-offer.json')['sdp']! as String;
    peers = FakePeerFactory(offer);
    session = createDeviceStreamSessionWithTransports(
      credentials: () async {
        credentialCalls++;
        return credentials != null
            ? credentials(credentialCalls)
            : StreamCredentials(
                url: 'wss://stream.example.test/v1/devices/d1/stream',
                token: 'token-$credentialCalls',
              );
      },
      transports: StreamTransports(signalling: connector, peers: peers),
      config: config,
      scheduler: scheduler,
      random: () => 0.5,
      sessionId: () => sessionId,
    );
    session.status.addListener(() => statuses.add(session.status.value));
  }

  final FakeScheduler scheduler = FakeScheduler();
  late final FakeConnector connector;
  late final FakePeerFactory peers;
  late final DeviceStreamSession session;
  final List<StreamStatus> statuses = [];
  int credentialCalls = 0;

  FakeConnection get ws => connector.last;
  FakePeer get peer => peers.last;

  /// Runs the happy path up to a connected stream.
  Future<void> connect() async {
    session.start();
    await pump();
    ws.receive(example('server-rtc-configuration.json'));
    await pump();
    ws.receive(example('server-answer.json'));
    await pump();
    peer.emitState(PeerState.connected);
    peer.controlChannel.setState(ChannelState.open);
    peer.hoverChannel.setState(ChannelState.open);
    await pump();
  }

  /// Advances the virtual clock by [ms] and lets the resulting work run.
  Future<void> advance(int ms) async {
    scheduler.advanceTo(scheduler.nowMs + ms);
    await pump();
  }
}
