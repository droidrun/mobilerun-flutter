// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/reconnect_policy.dart';
import 'package:mobilerun_flutter/src/core/stream_transports.dart';

import 'support/fake_transports.dart';
import 'support/harness.dart';

void main() {
  group('credentials discovery and cached recovery', () {
    test(
      'token refresh after recovery is stored until the next mount',
      () async {
        final refreshed = Completer<StreamCredentials?>();
        final h = Harness(
          credentials: (call) => call == 1
              ? const StreamCredentials(
                  url: 'wss://stream.example.test/s',
                  token: 'old',
                )
              : refreshed.future,
        );
        await h.connect();
        h.peer.emitState(PeerState.disconnected);
        h.peer.emitState(PeerState.connected);
        refreshed.complete(
          const StreamCredentials(
            url: 'wss://stream.example.test/s',
            token: 'fresh',
          ),
        );
        await pump();
        expect(h.connector.connections, hasLength(1));
        expect(h.peer.closed, isFalse);
        h.ws.serverClose();
        await pump();
        await h.advance(2000);
        expect(h.connector.connections, hasLength(2));
        expect(h.connector.uris.last.queryParameters['token'], 'fresh');
        await h.session.close();
      },
    );

    test('URL refresh after recovery remounts a connected stream', () async {
      final refreshed = Completer<StreamCredentials?>();
      final h = Harness(
        credentials: (call) => call == 1
            ? const StreamCredentials(
                url: 'wss://stream.example.test/old',
                token: 'old',
              )
            : refreshed.future,
      );
      await h.connect();
      final first = h.peer;
      h.peer.emitState(PeerState.disconnected);
      h.peer.emitState(PeerState.connected);
      refreshed.complete(
        const StreamCredentials(
          url: 'wss://stream.example.test/new',
          token: 'fresh',
        ),
      );
      await pump();
      expect(h.connector.connections, hasLength(2));
      expect(h.connector.uris.last.path, '/new');
      expect(first.closed, isTrue);
      await h.session.close();
    });

    const target = StreamCredentials(
      url: 'wss://stream.example.test/cached',
      token: 'stable',
    );
    test(
      'null recovery retains target and exhausts budget, then Retry connects',
      () async {
        var ready = false;
        final h = Harness(
          credentials: (call) => call == 1 || ready ? target : null,
        );
        await h.connect();
        h.connector.failWith = StateError('offline');
        h.ws.serverClose();
        await pump();
        expect(h.credentialCalls, 2);
        for (final delay in [1000, 2000, 4000, 8000, 16000, 30000]) {
          await h.advance(delay);
        }
        expect(h.session.status.value, const StreamUnavailable());
        expect(h.credentialCalls, 2); // No null polling after discovery.
        expect(h.connector.uris.every((u) => u.path == '/cached'), isTrue);
        ready = true;
        h.connector.failWith = null;
        h.session.retry();
        await h.connect();
        expect(h.session.status.value, const StreamConnected());
        expect(h.credentialCalls, 3);
        await h.session.close();
        expect(h.scheduler.pendingTimers, 0);
      },
    );

    test(
      'initial hung provider times out, then polls; late result is ignored',
      () async {
        final hung = Completer<StreamCredentials?>();
        final h = Harness(
          credentials: (call) => call == 1 ? hung.future : target,
        );
        h.session.start();
        await pump();
        await h.advance(InternalReconnectPolicy.connectTimeout.inMilliseconds);
        expect(h.session.status.value, const StreamConnecting());
        expect(h.credentialCalls, 1);
        await h.advance(2999);
        expect(h.credentialCalls, 1);
        await h.advance(1);
        expect(h.credentialCalls, 2);
        expect(h.connector.uris, hasLength(1));
        hung.complete(
          const StreamCredentials(
            url: 'wss://stale.example.test/s',
            token: 'stale',
          ),
        );
        await pump();
        expect(h.connector.uris, hasLength(1));
        await h.session.close();
        expect(h.scheduler.pendingTimers, 0);
      },
    );

    for (final retry in [false, true]) {
      test(
        '${retry ? "retry" : "wake"} supersedes initial hung call',
        () async {
          final hung = Completer<StreamCredentials?>();
          final h = Harness(
            credentials: (call) => call == 1 ? hung.future : target,
          );
          h.session.start();
          await pump();
          if (retry) {
            h.session.retry();
          } else {
            h.session.handleWake();
          }
          await pump();
          expect(h.credentialCalls, 2);
          expect(h.connector.uris, hasLength(1));
          hung.completeError(TimeoutException('stale integrator'));
          await pump();
          expect(h.connector.uris, hasLength(1));
          await h.session.close();
          expect(h.scheduler.pendingTimers, 0);
        },
      );
    }

    test(
      'hung background refresh never blocks mounts, wake or retry',
      () async {
        final hung = Completer<StreamCredentials?>();
        final h = Harness(
          credentials: (call) => call == 1 ? target : hung.future,
        );
        await h.connect();
        h.connector.failWith = StateError('offline');
        h.ws.serverClose();
        await pump();
        h.session.handleWake();
        await pump();
        expect(h.connector.uris, hasLength(2));
        expect(h.credentialCalls, 2);
        for (
          var i = 0;
          i < 10 && h.session.status.value is! StreamUnavailable;
          i++
        ) {
          await h.advance(45000);
        }
        expect(h.session.status.value, const StreamUnavailable());
        h.connector.failWith = null;
        h.session.retry();
        await h.connect();
        expect(h.session.status.value, const StreamConnected());
        expect(h.credentialCalls, 3);
        await h.session.close();
        hung.complete(null);
        await pump();
        expect(h.scheduler.pendingTimers, 0);
      },
    );
  });

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

    for (final reconnect in [false, true]) {
      test('latest URL waits for control (reconnect: $reconnect)', () async {
        final h = Harness();
        addTearDown(h.session.close);
        if (reconnect) {
          await h.connect();
          h.ws.serverClose();
          await pump();
        }
        h.session.openUrl('https://example.test/old');
        h.session.start();
        await pump();
        h.session.openUrl('https://example.test/latest');
        if (reconnect) await h.advance(1000);
        expect(h.ws.ofType('openUrl'), isEmpty);
        h.ws.receive(example('server-rtc-configuration.json'));
        await pump();
        expect(h.ws.ofType('openUrl'), isEmpty);
        h.peer.controlChannel.setState(ChannelState.open);
        await pump();
        expect(
          h.ws.ofType('openUrl').single.json['url'],
          'https://example.test/latest',
        );
      });
    }

    test('reports the video stream and its size', () async {
      final h = Harness();
      await h.connect();
      final stream = FakeMediaStream();
      h.peer.stats = const VideoStats(
        width: 488,
        height: 1080,
        framesDecoded: 5,
      );
      h.peer.emitVideo(stream);
      await pump();
      expect(h.session.videoStream.value, same(stream));
      expect(h.session.videoSize.value, const VideoSize(488, 1080));
      // A rotation of the device shows up on the next poll.
      h.peer.stats = const VideoStats(
        width: 1080,
        height: 488,
        framesDecoded: 9,
      );
      await h.advance(500);
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
      final h = Harness(
        credentials: (_) => const StreamCredentials(
          url: 'wss://stream.example.test/s',
          token: 'stable',
        ),
      );
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
      expect(h.credentialCalls, 3);
      expect(h.session.status.value, const StreamReconnecting(2));
      // The rejection refreshed in the background; the next mount reuses it.
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

    test(
      'null credentials poll every three seconds without failures',
      () async {
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
        expect(h.session.status.value, const StreamConnecting());
        await h.advance(2999);
        expect(h.credentialCalls, 1);
        await h.advance(1);
        expect(h.credentialCalls, 2);
        expect(h.session.status.value, const StreamConnecting());
        await h.advance(3000);
        expect(h.connector.connections, hasLength(1));
      },
    );

    test(
      'a throwing initial provider polls without consuming failures',
      () async {
        final h = Harness(credentials: (_) => throw StateError('offline'));
        h.session.start();
        await pump();
        expect(h.session.status.value, const StreamConnecting());
        await h.advance(3000);
        expect(h.credentialCalls, 2);
        expect(h.session.status.value, const StreamConnecting());
        await h.session.close();
      },
    );

    test('WebSocket open timeout (15 s) fails the attempt', () async {
      final h = Harness();
      h.connector.gate = Completer<void>();
      h.session.start();
      await pump();
      await h.advance(14999);
      expect(h.session.status.value, const StreamConnecting());
      await h.advance(1);
      expect(h.session.status.value, const StreamReconnecting(1));
    });

    test('a late-opening socket is closed', () async {
      final h = Harness();
      final gate = Completer<void>();
      h.connector.gate = gate;
      h.session.start();
      await pump();
      await h.advance(15000);
      gate.complete();
      await pump();
      expect(h.connector.connections.first.closedByClient, isTrue);
      expect(h.connector.connections.first.sent, isEmpty);
    });

    test('a socket that opens while close() runs is closed', () async {
      final h = Harness();
      final gate = Completer<void>();
      h.connector.gate = gate;
      h.session.start();
      await pump();
      await h.session.close();
      gate.complete();
      await pump();
      final socket = h.connector.connections.single;
      expect(socket.closedByClient, isTrue);
      expect(socket.sent, isEmpty);
      expect(h.peers.peers, isEmpty);
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

  test('peer closes while the signalling close is still pending', () async {
    final h = Harness();
    await h.connect();
    final gate = Completer<void>();
    h.ws.closeGate = gate;
    final closing = h.session.close();
    await pump();
    final peerClosed = h.peer.closed;
    gate.complete();
    await closing;
    expect(peerClosed, isTrue);
    expect(h.ws.closeCode, 1000);
  });

  group('screenshot', () {
    test('a request that cannot be sent reports not connected', () async {
      final h = Harness();
      await h.connect();
      addTearDown(h.session.close);
      h.ws.closedByServer = true;
      await expectLater(
        h.session.screenshot(),
        throwsA(isA<StreamNotConnectedException>()),
      );
    });

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
          isA<ScreenshotFailedException>().having(
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
      final outcome = expectLater(
        future,
        throwsA(isA<ScreenshotTimeoutException>()),
      );
      await h.advance(29999);
      await h.advance(1);
      await outcome;
      // A late reply is ignored: it neither throws nor disturbs the session.
      h.ws.receive({
        'type': 'screenshot',
        'id': h.ws.ofType('screenshot').single.json['id'],
        'dataUri': 'data:image/png;base64,AA==',
      });
      await pump();
      expect(h.session.status.value, const StreamConnected());
      expect(h.ws.closedByClient, isFalse);
    });

    test('request ids are unique and web-safe', () async {
      final h = Harness();
      await h.connect();
      unawaited(
        h.session.screenshot().then<void>((_) {}, onError: (Object _) {}),
      );
      unawaited(
        h.session.screenshot().then<void>((_) {}, onError: (Object _) {}),
      );
      await pump();
      final ids = [
        for (final f in h.ws.ofType('screenshot')) f.json['id']! as String,
      ];
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
      for (final id in ids) {
        expect(id, matches(RegExp(r'^ui-ss-\d+-\d+$')));
      }
      await h.session.close();
    });

    test('honours a custom timeout', () async {
      final h = Harness();
      await h.connect();
      final future = h.session.screenshot(timeout: const Duration(seconds: 2));
      final outcome = expectLater(
        future,
        throwsA(isA<ScreenshotTimeoutException>()),
      );
      await h.advance(2000);
      await outcome;
    });

    test('fails when not connected', () async {
      final h = Harness();
      await expectLater(
        h.session.screenshot(),
        throwsA(isA<StreamNotConnectedException>()),
      );
    });

    test('fails when the connection is lost meanwhile', () async {
      final h = Harness();
      await h.connect();
      final future = h.session.screenshot();
      final outcome = expectLater(
        future,
        throwsA(isA<StreamDisconnectedException>()),
      );
      await pump();
      h.ws.serverClose();
      await outcome;
    });
  });

  group('close()', () {
    test('awaits teardown already started by failure and remount', () async {
      final h = Harness();
      await h.connect();
      final oldPeer = h.peer;
      final oldSocket = h.ws;
      final gate = oldPeer.closeGate = Completer<void>();
      h.ws.serverClose();
      await pump();
      h.session.handleWake();
      await pump();
      var closed = false;
      final closing = h.session.close().then((_) => closed = true);
      await pump();
      expect(closed, isFalse);
      expect(oldPeer.closed, isFalse);
      gate.complete();
      await closing;
      expect(oldPeer.closed, isTrue);
      expect(oldSocket.closeCode, 1000);
      expect(h.scheduler.pendingTimers, 0);
    });

    test('releases peer, socket, channels and every timer', () async {
      final h = Harness();
      await h.connect();
      h.peer.emitVideo(FakeMediaStream());
      await pump();
      await h.session.close();
      expect(h.peer.closed, isTrue);
      expect(h.ws.closedByClient, isTrue);
      expect(h.ws.closeCode, 1000);
      expect(h.session.videoStream.value, isNull);
      expect(h.session.videoSize.value, isNull);
      expect(h.scheduler.pendingTimers, 0);
      // Nothing is sent or reported afterwards.
      final sentBefore = h.ws.sent.length;
      await h.advance(60000);
      expect(h.ws.sent.length, sentBefore);
      expect(h.session.sendControl(Uint8List(1)), isFalse);
      h.session.openUrl('https://example.test');
      expect(h.ws.sent.length, sentBefore);
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
        throwsA(isA<StreamDisconnectedException>()),
      );
      await pump();
      await h.session.close();
      await outcome;
    });
  });

  group('retry budget exhausted', () {
    test(
      'retires the last attempt; a late connected cannot restore it',
      () async {
        final h = Harness(
          credentials: (_) => const StreamCredentials(
            url: 'wss://stream.example.test/s',
            token: 'stable',
          ),
        );
        h.session.start();
        await pump();
        // Every attempt negotiates but never connects: the watchdog (45 s)
        // counts each as a failure. Backoff 1, 2, 4, 8, 16, 30 s.
        for (final backoff in const [1000, 2000, 4000, 8000, 16000, 30000, 0]) {
          h.ws.receive(example('server-rtc-configuration.json'));
          await pump();
          h.ws.receive(example('server-answer.json'));
          await pump();
          await h.advance(45000);
          if (backoff > 0) await h.advance(backoff);
        }
        expect(h.session.status.value, const StreamUnavailable());
        final lastPeer = h.peer;
        final lastSocket = h.ws;
        expect(lastPeer.closed, isTrue);
        expect(lastSocket.closedByClient, isTrue);
        expect(h.session.videoStream.value, isNull);
        expect(h.session.stats.value, isNull);

        // A peer event that arrives late changes nothing without retry().
        lastPeer.emitState(PeerState.connected);
        await pump();
        expect(h.session.status.value, const StreamUnavailable());
        await h.advance(120000);
        expect(h.session.status.value, const StreamUnavailable());
        expect(h.scheduler.pendingTimers, 0);
        expect(h.session.sendControl(Uint8List(1)), isFalse);

        h.session.retry();
        await pump();
        expect(h.session.status.value, const StreamReconnecting(0));
        expect(h.connector.connections, hasLength(8));
      },
    );
  });

  group('setMuted', () {
    test('audio is muted by default, setMuted reaches the live peer and '
        'later connections', () async {
      final h = Harness();
      await h.connect();
      expect(h.peer.muted, isTrue);
      h.session.setMuted(false);
      expect(h.peer.muted, isFalse);
      h.ws.serverClose();
      await pump();
      await h.advance(1000);
      h.ws.receive(example('server-rtc-configuration.json'));
      await pump();
      expect(h.peers.peers, hasLength(2));
      expect(h.peer.muted, isFalse);
    });

    test('StreamConfig.muted is the initial value', () async {
      final h = Harness(config: const StreamConfig(muted: false));
      await h.connect();
      expect(h.peer.muted, isFalse);
      h.session.setMuted(true);
      expect(h.peer.muted, isTrue);
    });
  });

  test('start() twice connects once', () async {
    final h = Harness();
    h.session.start();
    h.session.start();
    await pump();
    expect(h.connector.connections, hasLength(1));
  });
}
