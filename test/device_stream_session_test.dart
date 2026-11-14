// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';

import 'support/fake_scheduler.dart';
import 'support/fake_transports.dart';
import 'support/fixtures.dart';

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
    this.credentialCount = 1,
    StreamCredentials? Function(int call)? credentials,
  }) {
    connector = FakeConnector(scheduler);
    final offer = example('client-offer.json')['sdp']! as String;
    peers = FakePeerFactory(scheduler, offer);
    session = DeviceStreamSession.withTransports(
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
      scheduler: scheduler,
      random: () => 0.5,
      sessionId: () => sessionId,
    );
    session.status.addListener(() => statuses.add(session.status.value));
  }

  final int credentialCount;
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

void main() {
  group('happy path (sequence.json)', () {
    test('sends the fixture frames in order with the fixture timing', () async {
      final h = Harness();
      h.session.start();
      await pump();

      // Step 1 and 3: socket opens with the token, rtcConfiguration requested
      // right away.
      expect(h.connector.uris.single.queryParameters, {'token': 'token-1'});
      expect(h.ws.sent.map((f) => f.type), ['requestRtcConfiguration']);
      expect(
        h.ws.sent.single.json,
        example('client-request-rtc-configuration.json'),
      );
      expect(h.peers.peers, isEmpty);

      // Step 4-7: config -> peer connection -> offer.
      h.ws.receive(example('server-rtc-configuration.json'));
      await pump();
      expect(h.peers.configurations.single, {
        'iceServers':
            (example('server-rtc-configuration.json')['rtcConfiguration']!
                as Map)['iceServers'],
      });
      expect(h.peer.calls, ['createOffer']);
      expect(h.ws.sent.map((f) => f.type), [
        'requestRtcConfiguration',
        'offer',
      ]);
      expect(h.ws.sent.last.json, example('client-offer.json'));

      // Step 8: local candidates go out immediately, before the answer.
      final candidate = example('client-candidate.json');
      h.peer.emitLocalCandidate(
        IceCandidateData(
          candidate: candidate['candidate']! as String,
          sdpMid: candidate['sdpMid'] as String?,
          sdpMLineIndex: candidate['sdpMLineIndex'] as int?,
        ),
      );
      expect(h.ws.sent.last.json, candidate);

      // Step 9-11: answer applied.
      h.ws.receive(example('server-answer.json'));
      await pump();
      expect(h.peer.calls, ['createOffer', 'setRemoteAnswer']);

      // Step 14: connected is reported only when the peer connection says so.
      expect(h.session.status.value, const StreamConnecting());
      h.peer.emitState(PeerState.connecting);
      expect(h.session.status.value, const StreamConnecting());
      h.peer.emitState(PeerState.connected);
      expect(h.session.status.value, const StreamConnected());

      // Step 12: requestFrame x12, 125 ms apart, starting when control opens.
      await h.advance(3000);
      final openAt = h.scheduler.nowMs;
      expect(h.ws.ofType('requestFrame'), isEmpty);
      h.peer.controlChannel.setState(ChannelState.open);
      await h.advance(2000);
      final frames = h.ws.ofType('requestFrame');
      expect(frames, hasLength(12));
      expect(frames.map((f) => f.atMs - openAt), [
        for (var i = 0; i < 12; i++) i * 125,
      ]);
      expect(frames.first.json, example('client-request-frame.json'));
    });

    test('keepAlive is armed at mount and ticks every 10 s', () async {
      final h = Harness();
      h.session.start();
      await pump();
      await h.advance(9999);
      expect(h.ws.ofType('keepAlive'), isEmpty);
      await h.advance(1);
      expect(h.ws.ofType('keepAlive').single.atMs, 10000);
      expect(
        h.ws.ofType('keepAlive').single.json,
        example('client-keep-alive.json'),
      );
      await h.advance(20000);
      expect(h.ws.ofType('keepAlive').map((f) => f.atMs), [
        10000,
        20000,
        30000,
      ]);
    });

    test(
      'openUrl decodes percent-encoding and is dropped while offline',
      () async {
        final h = Harness();
        expect(h.session.openUrl('https://example.test'), isFalse);
        h.session.start();
        await pump();
        expect(h.session.openUrl('https://example.test/path?q=a%20b'), isTrue);
        expect(
          h.ws.ofType('openUrl').single.json,
          example('client-open-url.json'),
        );
      },
    );

    test('reports the video stream and its size', () async {
      final h = Harness();
      await h.connect();
      final stream = FakeMediaStream();
      h.peer.size = const VideoSize(488, 1080);
      h.peer.emitVideo(stream);
      await h.advance(0);
      expect(h.session.videoStream.value, same(stream));
      expect(h.session.videoSize.value, const VideoSize(488, 1080));
      // A rotation of the device shows up on the next poll.
      h.peer.size = const VideoSize(1080, 488);
      await h.advance(600);
      expect(h.session.videoSize.value, const VideoSize(1080, 488));
    });
  });

  group('candidate buffering', () {
    test(
      'candidates before the answer are buffered, then added in order',
      () async {
        final h = Harness();
        h.session.start();
        await pump();
        h.ws.receive(example('server-rtc-configuration.json'));
        await pump();
        Map<String, Object?> candidate(String line) => {
          'type': 'candidate',
          'candidate': line,
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        };
        h.ws.receive(candidate('candidate:a'));
        h.ws.receive(candidate('candidate:b'));
        await pump();
        expect(h.peer.calls, ['createOffer']);
        h.ws.receive(example('server-answer.json'));
        await pump();
        expect(h.peer.calls, [
          'createOffer',
          'setRemoteAnswer',
          'addCandidate candidate:a',
          'addCandidate candidate:b',
        ]);
        h.ws.receive(candidate('candidate:c'));
        await pump();
        expect(h.peer.calls.last, 'addCandidate candidate:c');
      },
    );

    test(
      'answer and candidate without a peer connection are dropped',
      () async {
        final h = Harness();
        h.session.start();
        await pump();
        h.ws.receive(example('server-answer.json'));
        h.ws.receive(example('server-candidate.json'));
        await pump();
        expect(h.peers.peers, isEmpty);
        expect(h.session.status.value, const StreamConnecting());
      },
    );
  });

  group('mid-session rtcConfiguration refresh', () {
    final refresh = example('server-rtc-configuration.json');

    test(
      'sets the servers and restarts ICE, buffering until the answer',
      () async {
        final h = Harness();
        await h.connect();
        h.peer.calls.clear();
        h.ws.receive(refresh);
        await pump();
        expect(h.peer.calls, ['setIceServers', 'createOffer(iceRestart)']);
        final offers = h.ws.ofType('offer');
        expect(offers, hasLength(2));
        expect(offers.last.json['sdp'], endsWith('#restart'));

        // Candidates of the new ICE generation wait for the restart answer.
        h.ws.receive({
          'type': 'candidate',
          'candidate': 'candidate:r',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        });
        await pump();
        expect(h.peer.calls, ['setIceServers', 'createOffer(iceRestart)']);
        h.ws.receive(example('server-answer.json'));
        await pump();
        expect(h.peer.calls.skip(2), [
          'setRemoteAnswer',
          'addCandidate candidate:r',
        ]);
        expect(h.session.status.value, const StreamConnected());
      },
    );

    test('a refresh without iceServers is ignored', () async {
      final h = Harness();
      await h.connect();
      h.peer.calls.clear();
      h.ws.receive(example('server-rtc-configuration.json', 1));
      await pump();
      expect(h.peer.calls, isEmpty);
      expect(h.ws.ofType('offer'), hasLength(1));
    });

    test('a failing setConfiguration skips the ICE restart', () async {
      final h = Harness();
      await h.connect();
      h.peer.setIceServersError = StateError('rejected');
      h.peer.calls.clear();
      h.ws.receive(refresh);
      await pump();
      expect(h.peer.calls, ['setIceServers']);
      expect(h.ws.ofType('offer'), hasLength(1));
      // No grace window was opened.
      h.peer.emitState(PeerState.disconnected);
      expect(h.session.status.value, isA<StreamReconnecting>());
    });

    test('a dip during the grace window is suppressed', () async {
      final h = Harness();
      await h.connect();
      h.ws.receive(refresh);
      await pump();
      h.peer.emitState(PeerState.connecting);
      h.peer.emitState(PeerState.disconnected);
      expect(h.session.status.value, const StreamConnected());
      await h.advance(14999);
      expect(h.session.status.value, const StreamConnected());
      // Recovering ends the grace window and nothing was reported.
      h.peer.emitState(PeerState.connected);
      await h.advance(20000);
      expect(h.session.status.value, const StreamConnected());
      expect(h.connector.connections, hasLength(1));
    });

    test(
      'a dip that outlives the grace window is reported at its end',
      () async {
        final h = Harness();
        await h.connect();
        h.ws.receive(refresh);
        await pump();
        final restartedAt = h.scheduler.nowMs;
        h.peer.emitState(PeerState.disconnected);
        await h.advance(14999);
        expect(h.session.status.value, const StreamConnected());
        await h.advance(1);
        expect(h.scheduler.nowMs - restartedAt, 15000);
        expect(h.session.status.value, const StreamReconnecting(1));
      },
    );

    test('failed passes through the grace window', () async {
      final h = Harness();
      await h.connect();
      h.ws.receive(refresh);
      await pump();
      h.peer.emitState(PeerState.failed);
      expect(h.session.status.value, const StreamReconnecting(1));
    });
  });

  group('failures rebuild the whole session', () {
    test('WS close while connected -> reconnecting -> full rebuild', () async {
      final h = Harness();
      await h.connect();
      final firstPeer = h.peer;
      final firstWs = h.ws;
      firstWs.serverClose();
      await pump();
      expect(h.session.status.value, const StreamReconnecting(1));
      // Everything of the dead attempt is released right away.
      expect(firstPeer.closed, isTrue);
      expect(h.session.videoStream.value, isNull);

      // Backoff: attempt 1 waits 1 s (random 0.5 -> no jitter).
      await h.advance(999);
      expect(h.connector.connections, hasLength(1));
      await h.advance(1);
      expect(h.connector.connections, hasLength(2));
      expect(h.ws, isNot(same(firstWs)));
      // The new socket runs the whole handshake again, with a new peer.
      expect(h.ws.ofType('requestRtcConfiguration'), hasLength(1));
      h.ws.receive(example('server-rtc-configuration.json'));
      await pump();
      expect(h.peers.peers, hasLength(2));
      expect(h.peer, isNot(same(firstPeer)));
      expect(h.ws.ofType('offer'), hasLength(1));
      // rtcConfiguration is requested per connection, never cached.
      h.ws.receive(example('server-answer.json'));
      await pump();
      h.peer.emitState(PeerState.connected);
      expect(h.session.status.value, const StreamConnected());
      expect(
        h.statuses,
        [
          const StreamConnecting(),
          const StreamConnected(),
          const StreamReconnecting(1),
          const StreamConnected(),
        ].sublist(1),
      );
    });

    test('peer connection failed -> rebuild', () async {
      final h = Harness();
      await h.connect();
      final firstPeer = h.peer;
      firstPeer.emitState(PeerState.failed);
      expect(h.session.status.value, const StreamReconnecting(1));
      await pump();
      expect(firstPeer.closed, isTrue);
      expect(h.ws.closedByClient, isTrue);
      await h.advance(1000);
      expect(h.connector.connections, hasLength(2));
    });

    test('peer connection closed -> rebuild', () async {
      final h = Harness();
      await h.connect();
      h.peer.emitState(PeerState.closed);
      expect(h.session.status.value, const StreamReconnecting(1));
    });

    test('a transient disconnect does not rebuild if it recovers', () async {
      final h = Harness();
      await h.connect();
      h.peer.emitState(PeerState.disconnected);
      expect(h.session.status.value, const StreamReconnecting(1));
      h.peer.emitState(PeerState.connected);
      expect(h.session.status.value, const StreamConnected());
      await h.advance(5000);
      expect(h.connector.connections, hasLength(1));
    });

    test('credentials are asked again when the cycle heals', () async {
      final h = Harness();
      await h.connect();
      expect(h.credentialCalls, 1);
      h.ws.serverClose();
      await pump();
      await h.advance(1000);
      expect(h.credentialCalls, 2);
      expect(h.connector.uris.last.queryParameters['token'], 'token-2');
    });

    test('token rejected (401 on open) -> credentials asked again', () async {
      final h = Harness();
      await h.connect();
      h.ws.serverClose(); // cycle heal -> call 2 on the next attempt
      await pump();
      h.connector.failWith = const SignallingRejectedException(401);
      await h.advance(1000);
      expect(h.credentialCalls, 2);
      expect(h.session.status.value, const StreamReconnecting(2));
      // The next attempt, in the same cycle, asks again because of the 401.
      h.connector.failWith = null;
      await h.advance(2000);
      expect(h.credentialCalls, 3);
      expect(h.connector.uris.last.queryParameters['token'], 'token-3');
    });

    test('a failure that is not a rejection reuses the credentials', () async {
      final h = Harness();
      h.connector.failWith = StateError('network down');
      h.session.start();
      await pump();
      // Heal of the first failure: credentials asked again on the next try.
      await h.advance(1000);
      expect(h.credentialCalls, 2);
      await h.advance(2000);
      // Same cycle, no rejection: no new request.
      expect(h.credentialCalls, 2);
    });

    test('null credentials count as a failure and are retried', () async {
      final h = Harness(
        credentials: (call) => call < 3
            ? null
            : const StreamCredentials(
                url: 'wss://stream.example.test/s',
                token: 't',
              ),
      );
      h.session.start();
      await pump();
      expect(h.connector.connections, isEmpty);
      expect(h.session.status.value, const StreamReconnecting(1));
      await h.advance(1000);
      expect(h.session.status.value, const StreamReconnecting(2));
      await h.advance(2000);
      expect(h.connector.connections, hasLength(1));
    });

    test('a throwing credentials provider counts as a failure', () async {
      final h = Harness(credentials: (_) => throw StateError('offline'));
      h.session.start();
      await pump();
      expect(h.session.status.value, const StreamReconnecting(1));
    });

    test('WebSocket open timeout (15 s) fails the attempt', () async {
      final h = Harness();
      h.connector.gate = Completer<FakeConnection>();
      h.session.start();
      await pump();
      await h.advance(14999);
      expect(h.session.status.value, const StreamConnecting());
      await h.advance(1);
      expect(h.session.status.value, const StreamReconnecting(1));
      // A socket that opens late is closed, not used.
      final late = h.connector.connections.first;
      h.connector.gate = null;
      expect(late.closedByClient, isFalse);
    });

    test('a late-opening socket is closed', () async {
      final h = Harness();
      final gate = Completer<FakeConnection>();
      h.connector.gate = gate;
      h.session.start();
      await pump();
      await h.advance(15000);
      gate.complete(h.connector.connections.first);
      await pump();
      expect(h.connector.connections.first.closedByClient, isTrue);
      expect(h.connector.connections.first.sent, isEmpty);
    });

    test('rtcConfiguration timeout (15 s) fails the attempt', () async {
      final h = Harness();
      h.session.start();
      await pump();
      await h.advance(14999);
      expect(h.session.status.value, const StreamConnecting());
      await h.advance(1);
      expect(h.session.status.value, const StreamReconnecting(1));
      expect(h.peers.peers, isEmpty);
    });

    test(
      'invalid JSON while awaiting rtcConfiguration fails startup',
      () async {
        final h = Harness();
        h.session.start();
        await pump();
        h.ws.receive('not json');
        await pump();
        expect(h.session.status.value, const StreamReconnecting(1));
      },
    );

    test(
      'other valid messages while awaiting rtcConfiguration are ignored',
      () async {
        final h = Harness();
        h.session.start();
        await pump();
        h.ws.receive(example('server-answer.json'));
        h.ws.receive({'type': 'surprise'});
        await pump();
        expect(h.session.status.value, const StreamConnecting());
        h.ws.receive(example('server-rtc-configuration.json'));
        await pump();
        expect(h.peers.peers, hasLength(1));
      },
    );

    test('invalid JSON and unknown types once active are dropped', () async {
      final h = Harness();
      await h.connect();
      h.ws.receive('not json');
      h.ws.receive({'type': 'surprise'});
      h.ws.receive([1, 2]);
      await pump();
      expect(h.session.status.value, const StreamConnected());
    });

    test(
      'becomes unavailable after 6 failed retries, retry() starts over',
      () async {
        final h = Harness();
        h.connector.failWith = StateError('down');
        h.session.start();
        await pump();
        // Backoff 1, 2, 4, 8, 16, 30 s (random 0.5 -> no jitter).
        for (final wait in [1000, 2000, 4000, 8000, 16000, 30000]) {
          expect(h.session.status.value, isA<StreamReconnecting>());
          await h.advance(wait);
        }
        expect(h.session.status.value, const StreamUnavailable());
        await h.advance(120000);
        expect(h.session.status.value, const StreamUnavailable());

        h.connector.failWith = null;
        h.session.retry();
        await pump();
        expect(h.session.status.value, const StreamReconnecting(0));
        h.ws.receive(example('server-rtc-configuration.json'));
        await pump();
        h.ws.receive(example('server-answer.json'));
        await pump();
        h.peer.emitState(PeerState.connected);
        expect(h.session.status.value, const StreamConnected());
      },
    );
  });

  group('data channels', () {
    test('control and hover sends are dropped while not open', () async {
      final h = Harness();
      expect(h.session.sendControl(Uint8List(1)), isFalse);
      expect(h.session.sendHover(Uint8List(1)), isFalse);
      h.session.start();
      await pump();
      h.ws.receive(example('server-rtc-configuration.json'));
      await pump();
      expect(h.session.sendControl(Uint8List(1)), isFalse);
      expect(h.session.sendHover(Uint8List(1)), isFalse);
      expect(h.peer.controlChannel.sent, isEmpty);
      expect(h.peer.hoverChannel.sent, isEmpty);
    });

    test(
      'hover goes only to the hover channel, control only to control',
      () async {
        final h = Harness();
        await h.connect();
        final control = Uint8List.fromList([1, 2, 3]);
        final hover = Uint8List.fromList([9]);
        expect(h.session.sendControl(control), isTrue);
        expect(h.session.sendHover(hover), isTrue);
        expect(h.peer.controlChannel.sent, [control]);
        expect(h.peer.hoverChannel.sent, [hover]);
      },
    );

    test('a hover message is dropped, never sent on control, when hover is '
        'not open', () async {
      final h = Harness();
      await h.connect();
      h.peer.hoverChannel.setState(ChannelState.closed);
      expect(h.session.sendHover(Uint8List(1)), isFalse);
      expect(h.peer.controlChannel.sent, isEmpty);
    });

    test('sends are dropped after the channel closed', () async {
      final h = Harness();
      await h.connect();
      h.peer.controlChannel.setState(ChannelState.closing);
      expect(h.session.sendControl(Uint8List(1)), isFalse);
    });
  });

  group('screenshot', () {
    test('returns the decoded image', () async {
      final h = Harness();
      await h.connect();
      final future = h.session.screenshot();
      await pump();
      final request = h.ws.ofType('screenshot').single.json;
      expect(request['id'], startsWith('ui-ss-'));
      h.ws.receive({
        'type': 'screenshot',
        'id': request['id'],
        'dataUri': 'data:image/png;base64,${base64Encode([1, 2, 3, 4])}',
      });
      expect(await future, [1, 2, 3, 4]);
    });

    test('an error reply fails the request with its message', () async {
      final h = Harness();
      await h.connect();
      final future = h.session.screenshot();
      await pump();
      h.ws.receive({
        'type': 'screenshotError',
        'id': h.ws.ofType('screenshot').single.json['id'],
        'message': 'device busy',
      });
      await expectLater(
        future,
        throwsA(
          isA<StreamSessionException>().having(
            (e) => e.message,
            'message',
            'device busy',
          ),
        ),
      );
    });

    test('a reply for an unknown id is ignored', () async {
      final h = Harness();
      await h.connect();
      final future = h.session.screenshot();
      unawaited(future.then<void>((_) {}, onError: (Object _) {}));
      await pump();
      h.ws.receive({'type': 'screenshot', 'id': 'other', 'dataUri': 'x,AA=='});
      await pump();
      h.ws.receive({
        'type': 'screenshot',
        'id': h.ws.ofType('screenshot').single.json['id'],
        'dataUri': 'data:image/png;base64,AA==',
      });
      expect(await future, [0]);
    });

    test('times out after 30 s', () async {
      final h = Harness();
      await h.connect();
      final future = h.session.screenshot();
      final outcome = expectLater(future, throwsA(isA<TimeoutException>()));
      await h.advance(29999);
      await h.advance(1);
      await outcome;
      // A late reply is ignored.
      h.ws.receive({
        'type': 'screenshot',
        'id': h.ws.ofType('screenshot').single.json['id'],
        'dataUri': 'data:image/png;base64,AA==',
      });
      await pump();
    });

    test('honours a custom timeout', () async {
      final h = Harness();
      await h.connect();
      final future = h.session.screenshot(timeout: const Duration(seconds: 2));
      final outcome = expectLater(future, throwsA(isA<TimeoutException>()));
      await h.advance(2000);
      await outcome;
    });

    test('fails when not connected', () async {
      final h = Harness();
      await expectLater(
        h.session.screenshot(),
        throwsA(isA<StreamSessionException>()),
      );
    });

    test('fails when the connection is lost meanwhile', () async {
      final h = Harness();
      await h.connect();
      final future = h.session.screenshot();
      final outcome = expectLater(
        future,
        throwsA(isA<StreamSessionException>()),
      );
      await pump();
      h.ws.serverClose();
      await outcome;
    });
  });

  group('close()', () {
    test('releases peer, socket, channels and every timer', () async {
      final h = Harness();
      await h.connect();
      h.peer.emitVideo(FakeMediaStream());
      await pump();
      await h.session.close();
      expect(h.peer.closed, isTrue);
      expect(h.ws.closedByClient, isTrue);
      expect(h.session.videoStream.value, isNull);
      expect(h.session.videoSize.value, isNull);
      expect(h.scheduler.pendingTimers, 0);
      // Nothing is sent or reported afterwards.
      final sentBefore = h.ws.sent.length;
      await h.advance(60000);
      expect(h.ws.sent.length, sentBefore);
      expect(h.session.sendControl(Uint8List(1)), isFalse);
      expect(h.session.openUrl('https://example.test'), isFalse);
    });

    test('is silent: closing never counts as a failure', () async {
      final h = Harness();
      await h.connect();
      h.statuses.clear();
      await h.session.close();
      await h.advance(60000);
      expect(h.statuses, isEmpty);
      expect(h.connector.connections, hasLength(1));
    });

    test('during a backoff wait cancels the reconnect', () async {
      final h = Harness();
      await h.connect();
      h.ws.serverClose();
      await pump();
      await h.session.close();
      await h.advance(60000);
      expect(h.connector.connections, hasLength(1));
      expect(h.scheduler.pendingTimers, 0);
    });

    test('while connecting releases the half-open attempt', () async {
      final h = Harness();
      h.session.start();
      await pump();
      await h.session.close();
      expect(h.ws.closedByClient, isTrue);
      expect(h.scheduler.pendingTimers, 0);
    });

    test('start() after close() does nothing', () async {
      final h = Harness();
      await h.session.close();
      h.session.start();
      await pump();
      expect(h.connector.connections, isEmpty);
    });

    test('fails a pending screenshot', () async {
      final h = Harness();
      await h.connect();
      final future = h.session.screenshot();
      final outcome = expectLater(
        future,
        throwsA(isA<StreamSessionException>()),
      );
      await pump();
      await h.session.close();
      await outcome;
    });
  });

  test('start() twice connects once', () async {
    final h = Harness();
    h.session.start();
    h.session.start();
    await pump();
    expect(h.connector.connections, hasLength(1));
  });

  test('credentials never show up in toString', () {
    const credentials = StreamCredentials(
      url: 'wss://x.test/s',
      token: 'secret',
    );
    expect(credentials.toString(), isNot(contains('secret')));
  });
}
