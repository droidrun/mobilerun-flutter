// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/stream_transports.dart';

import 'support/fake_transports.dart';
import 'support/harness.dart';

const publishCapabilities = DevicePublishCapabilities(
  microphoneInjection: true,
  cameraInjection: true,
  mediaInjectionTransport: 'direct',
);
const microphone = PublishOptions(audio: true);
const camera = PublishOptions(audio: true, video: true);

void respond(Harness h, String state, {Object? reason, String? id}) {
  h.ws.receive({
    'type': 'publishState',
    'mediaSessionId': id ?? h.session.publishState.value.mediaSessionId,
    'state': state,
    'reason': ?reason,
  });
}

Matcher fails(String reason, {String? detail}) => throwsA(
  isA<PublishException>()
      .having((e) => e.failure.reason.code, 'reason', reason)
      .having((e) => e.failure.detail, 'detail', detail),
);

void main() {
  late Harness h;
  late FakePublishCapture capture;
  setUp(() {
    capture = FakePublishCapture();
    h = Harness(
      config: const StreamConfig(publishCapabilities: publishCapabilities),
      publishCapture: capture,
    );
    addTearDown(() => h.session.close());
  });

  test(
    'audio then video attach only after accepted; resolves after active',
    () async {
      await h.connect();
      final phases = <PublishPhase>[];
      h.session.publishState.addListener(
        () => phases.add(h.session.publishState.value.phase),
      );
      final start = h.session.startPublish(camera);
      await pump();
      expect(capture.calls, 1);
      expect(h.peer.publishCalls, isEmpty);
      final frame = h.ws.ofType('publishStart').single.json;
      final id = frame['mediaSessionId'];
      expect(
        id,
        matches(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ),
        ),
      );
      expect(id, isNot(sessionId));
      expect(frame, {
        'type': 'publishStart',
        'mediaSessionId': id,
        'kinds': ['audio', 'video'],
      });
      respond(h, 'accepted');
      await pump();
      expect(h.peer.publishCalls, ['audio:attach', 'video:attach']);
      expect(h.session.publishState.value.phase, PublishPhase.accepted);
      respond(h, 'active');
      expect((await start).phase, PublishPhase.active);
      expect(phases, [
        PublishPhase.capturing,
        PublishPhase.starting,
        PublishPhase.accepted,
        PublishPhase.active,
      ]);
      expect(h.session.status.value, isA<StreamConnected>());
      expect(h.errors, isEmpty);
    },
  );

  test(
    'active implies acceptance and latches until delayed attachment',
    () async {
      await h.connect();
      final gate = h.peer.attachGate = Completer<void>();
      final start = h.session.startPublish(camera);
      var resolved = false;
      unawaited(start.then((_) => resolved = true));
      await pump();
      respond(h, 'active');
      await pump();
      expect(resolved, isFalse);
      expect(h.session.publishState.value.phase, PublishPhase.accepted);
      gate.complete();
      expect((await start).phase, PublishPhase.active);
      expect(h.peer.publishCalls, ['audio:attach', 'video:attach']);
    },
  );

  for (final row in [
    ('forbidden', 'publish_not_allowed'),
    ('unsupported', 'publish_unsupported'),
    ('busy', 'publish_busy'),
    ('inject_failed', 'publish_failed'),
    ('source_lost', 'publish_failed'),
    ('connection_closed', 'disconnected'),
    ('future_reason', 'publish_failed'),
  ]) {
    test('server ${row.$1} maps to ${row.$2} and releases capture', () async {
      await h.connect();
      final result = expectLater(h.session.startPublish(camera), fails(row.$2));
      await pump();
      respond(h, 'rejected', reason: row.$1);
      await result;
      expect(
        capture.media.single.tracks.every((track) => track.stopped),
        isTrue,
      );
      expect(
        h.peer.publishCalls.where((call) => call.endsWith('attach')),
        isEmpty,
      );
      expect(h.session.publishState.value.serverReason, row.$1);
      expect(h.session.publishState.value.reason, row.$2);
      expect(h.errors.single.reason.code, row.$2);
      expect(h.errors.single.operation, 'publish');
      expect(h.errors.single.isFinal, isTrue);
      expect(h.errors.single.attempt, 0);
      expect(
        h.errors.single.mediaSessionId,
        h.session.publishState.value.mediaSessionId,
      );
      expect(h.session.status.value, isA<StreamConnected>());
      expect(h.ws.ofType('stopPublish').single.json, {
        'type': 'stopPublish',
        'mediaSessionId': h.session.publishState.value.mediaSessionId,
      });
    });
  }

  test('silence crosses 5000 ms and is unsupported, never forbidden', () async {
    await h.connect();
    final result = expectLater(
      h.session.startPublish(microphone),
      fails('publish_unsupported', detail: 'response_timeout'),
    );
    await pump();
    await h.advance(4999);
    expect(h.session.publishState.value.phase, PublishPhase.starting);
    await h.advance(1);
    await result;
    respond(h, 'active');
    await pump();
    expect(h.errors, hasLength(1));
    expect(h.peer.publishCalls, ['audio:detach']);
    expect(capture.media.single.tracks.single.stopped, isTrue);
  });

  test('accepted replaces response timer; duplicate does not extend active deadline', () async {
    await h.connect();
    final result = expectLater(
      h.session.startPublish(microphone),
      fails('publish_timeout', detail: 'active_timeout'),
    );
    await pump();
    await h.advance(4999);
    respond(h, 'accepted');
    await pump();
    await h.advance(14999);
    expect(h.session.publishState.value.phase, PublishPhase.accepted);
    respond(h, 'accepted');
    await pump();
    await h.advance(1);
    await result;
    expect(h.peer.publishCalls, ['audio:attach', 'audio:detach']);
    expect(capture.media.single.tracks.single.stopped, isTrue);
  });

  test('concurrent start preserves original state and capture', () async {
    await h.connect();
    final first = h.session.startPublish(microphone);
    await pump();
    final previous = h.session.publishState.value;
    await expectLater(
      h.session.startPublish(camera),
      fails('publish_failed', detail: 'publish_in_progress'),
    );
    expect(h.session.publishState.value, same(previous));
    expect(capture.calls, 1);
    respond(h, 'active');
    await first;
    await expectLater(
      h.session.startPublish(camera),
      fails('publish_failed', detail: 'already_publishing'),
    );
    expect(h.session.publishState.value.phase, PublishPhase.active);
    expect(h.ws.ofType('publishStart'), hasLength(1));
  });

  test(
    'permission denial uses structured failure without wire or viewer failure',
    () async {
      await h.connect();
      capture.error = const PublishException(
        PublishFailure(
          reason: StreamErrorReason.permissionDenied,
          message: 'Denied',
          detail: 'capture_permission',
        ),
      );
      await expectLater(
        h.session.startPublish(camera),
        fails('permission_denied', detail: 'capture_permission'),
      );
      expect(h.ws.ofType('publishStart'), isEmpty);
      expect(h.errors.single.operation, 'publish');
      expect(h.errors.single.mediaSessionId, isNull);
      expect(h.session.status.value, isA<StreamConnected>());
    },
  );

  test(
    'stop during capture cancels start and stops late inputs without signaling',
    () async {
      await h.connect();
      final gate = capture.gate = Completer<void>();
      final result = expectLater(
        h.session.startPublish(camera),
        fails('publish_cancelled'),
      );
      await pump();
      await h.session.stopPublish();
      await result;
      expect(h.session.publishState.value.phase, PublishPhase.stopped);
      expect(h.session.publishState.value.reason, 'stopped_by_client');
      gate.complete();
      await pump();
      expect(
        capture.media.single.tracks.every((track) => track.stopped),
        isTrue,
      );
      expect(h.ws.ofType('publishStart'), isEmpty);
      expect(
        h.peer.publishCalls.where((call) => call.endsWith('attach')),
        isEmpty,
      );
      expect(h.errors, isEmpty);
    },
  );

  test('stop while attachment pending releases inputs and fences a subsequent start', () async {
    await h.connect();
    final gate = h.peer.attachGate = Completer<void>();
    final result = expectLater(
      h.session.startPublish(camera),
      fails('publish_cancelled'),
    );
    await pump();
    respond(h, 'active');
    await pump();
    final stopping = h.session.stopPublish();
    await pump();
    expect(capture.media.single.tracks.every((track) => track.stopped), isTrue);
    final next = h.session.startPublish(microphone);
    await pump();
    expect(capture.calls, 1);
    h.peer.attachGate = null;
    gate.complete();
    await stopping;
    await result;
    await pump();
    respond(h, 'active');
    await next;
    expect(
      h.peer.attached[PublishKind.audio],
      same(capture.media.last.tracks.single),
    );
    expect(h.peer.attached[PublishKind.video], isNull);
    expect(h.ws.ofType('publishStart'), hasLength(2));
    expect(
      h.ws.ofType('publishStart').first.json['mediaSessionId'],
      isNot(h.ws.ofType('publishStart').last.json['mediaSessionId']),
    );
  });

  test(
    'cancel a queued second start without bypassing original sender cleanup',
    () async {
      await h.connect();
      final gate = h.peer.attachGate = Completer<void>();
      final first = expectLater(
        h.session.startPublish(camera),
        fails('publish_cancelled'),
      );
      await pump();
      respond(h, 'active');
      await pump();
      final stopFirst = h.session.stopPublish();
      final second = expectLater(
        h.session.startPublish(microphone),
        fails('publish_cancelled'),
      );
      final stopSecond = h.session.stopPublish();
      final third = h.session.startPublish(microphone);
      await pump();
      expect(capture.calls, 1);
      h.peer.attachGate = null;
      gate.complete();
      await stopFirst;
      await stopSecond;
      await first;
      await second;
      await pump();
      expect(capture.calls, 2);
      respond(h, 'active');
      await third;
      expect(
        h.peer.attached[PublishKind.audio],
        same(capture.media.last.tracks.single),
      );
      expect(h.peer.attached[PublishKind.video], isNull);
    },
  );

  test('video attach failure also stops and detaches the microphone', () async {
    await h.connect();
    h.peer.failAttach = PublishKind.video;
    final result = expectLater(
      h.session.startPublish(camera),
      fails('publish_failed', detail: 'attach_failed'),
    );
    await pump();
    respond(h, 'accepted');
    await result;
    expect(capture.media.single.tracks.every((track) => track.stopped), isTrue);
    expect(h.peer.attached.values, everyElement(isNull));
  });

  test('accepted with rejected senders is unsupported rather than a permission claim', () async {
    await h.connect();
    h.peer.usablePublishSenders = false;
    final result = expectLater(
      h.session.startPublish(microphone),
      fails('publish_unsupported', detail: 'negotiated_sender'),
    );
    await pump();
    respond(h, 'accepted');
    await result;
    expect(h.peer.publishCalls, ['audio:detach']);
  });

  test(
    'start write failure releases capture and reports disconnected',
    () async {
      await h.connect();
      h.ws.closedByServer = true;
      await expectLater(h.session.startPublish(camera), fails('disconnected'));
      expect(
        capture.media.single.tracks.every((track) => track.stopped),
        isTrue,
      );
      expect(h.peer.publishCalls, ['audio:detach', 'video:detach']);
      expect(h.errors.single.reason.code, 'disconnected');
      expect(h.errors.single.operation, 'publish');
      expect(h.ws.ofType('publishStart'), isEmpty);
    },
  );

  test(
    'socket loss cleans active capture and reconnect never resumes it',
    () async {
      await h.connect();
      final start = h.session.startPublish(camera);
      await pump();
      respond(h, 'active');
      await start;
      h.ws.serverClose();
      await pump();
      expect(
        capture.media.single.tracks.every((track) => track.stopped),
        isTrue,
      );
      expect(h.session.publishState.value.reason, 'disconnected');
      expect(h.errors.where((e) => e.operation == 'publish'), hasLength(1));
      await h.advance(1000);
      h.ws.receive(example('server-rtc-configuration.json'));
      await pump();
      h.peer.emitState(PeerState.connected);
      await pump();
      expect(capture.calls, 1);
      expect(h.ws.ofType('publishStart'), isEmpty);
    },
  );

  test('same-peer ICE refresh preserves publication and output mute is independent', () async {
    await h.connect();
    final start = h.session.startPublish(microphone);
    await pump();
    respond(h, 'active');
    await start;
    final id = h.session.publishState.value.mediaSessionId;
    h.ws.receive(example('server-rtc-configuration.json'));
    await pump();
    h.peer.emitState(PeerState.disconnected);
    h.session.setMuted(true);
    await pump();
    expect(h.session.publishState.value.mediaSessionId, id);
    expect(h.session.publishState.value.phase, PublishPhase.active);
    expect(capture.media.single.tracks.single.stopped, isFalse);
    expect(h.ws.ofType('publishStart'), hasLength(1));
  });

  test(
    'ended input terminates entire active session, not just that kind',
    () async {
      await h.connect();
      final start = h.session.startPublish(camera);
      await pump();
      respond(h, 'active');
      await start;
      capture.media.single.tracks.last.onEnded!();
      await pump();
      expect(h.session.publishState.value.detail, 'capture_unavailable');
      expect(
        capture.media.single.tracks.every((track) => track.stopped),
        isTrue,
      );
      expect(h.peer.attached.values, everyElement(isNull));
    },
  );

  test('audio false fails before permission or wire access', () async {
    await h.connect();
    await expectLater(
      h.session.startPublish(const PublishOptions(audio: false, video: true)),
      fails('publish_failed', detail: 'invalid_options'),
    );
    expect(capture.calls, 0);
    expect(h.ws.ofType('publishStart'), isEmpty);
  });

  test(
    'not connected fails before capture despite valid capabilities',
    () async {
      await expectLater(
        h.session.startPublish(microphone),
        fails('disconnected', detail: 'not_connected'),
      );
      expect(capture.calls, 0);
    },
  );

  test('no local H264 blocks camera but microphone works', () async {
    await h.connect();
    h.peer.publishKinds = {PublishKind.audio};
    await expectLater(
      h.session.startPublish(camera),
      fails('publish_unsupported', detail: 'local_media_support'),
    );
    expect(capture.calls, 0);
    final start = h.session.startPublish(microphone);
    await pump();
    respond(h, 'active');
    await start;
    expect(h.ws.ofType('publishStart').single.json['kinds'], ['audio']);
  });

  test(
    'unknown and foreign frames ignored; duplicate events do not attach twice',
    () async {
      await h.connect();
      final start = h.session.startPublish(microphone);
      await pump();
      respond(h, 'active', id: 'foreign');
      respond(h, 'future');
      h.ws.receive({
        'type': 'publishState',
        'mediaSessionId': 3,
        'state': 'active',
      });
      await pump();
      expect(h.peer.publishCalls, isEmpty);
      respond(h, 'accepted');
      respond(h, 'accepted');
      respond(h, 'active');
      respond(h, 'active');
      await start;
      expect(h.peer.publishCalls, ['audio:attach']);
      await h.session.stopPublish();
      final terminal = h.session.publishState.value;
      await h.session.stopPublish();
      respond(h, 'rejected', reason: 'forbidden');
      await pump();
      expect(h.session.publishState.value, same(terminal));
      expect(h.ws.ofType('stopPublish'), hasLength(1));
      expect(h.errors, isEmpty);
    },
  );

  test(
    'non-string terminal reason is absent and unexpected remote stop fails',
    () async {
      await h.connect();
      final result = expectLater(
        h.session.startPublish(microphone),
        fails('publish_failed'),
      );
      await pump();
      respond(h, 'error', reason: 123);
      await result;
      expect(h.session.publishState.value.serverReason, isNull);
      final next = expectLater(
        h.session.startPublish(microphone),
        fails('publish_failed', detail: 'remote_stop'),
      );
      await pump();
      respond(h, 'stopped', reason: 'stopped_by_client');
      await next;
    },
  );

  test(
    'closed session rejects future starts and late capture stays silent',
    () async {
      await h.connect();
      final gate = capture.gate = Completer<void>();
      final result = expectLater(
        h.session.startPublish(camera),
        fails('publish_cancelled'),
      );
      await pump();
      var callbacks = 0;
      h.session.publishState.addListener(() => callbacks++);
      await h.session.close();
      await result;
      gate.complete();
      await pump();
      expect(
        capture.media.single.tracks.every((track) => track.stopped),
        isTrue,
      );
      expect(callbacks, 0);
      await expectLater(
        h.session.startPublish(microphone),
        fails('disconnected', detail: 'session_closed'),
      );
      expect(h.errors, isEmpty);
    },
  );

  for (final row in <(DevicePublishCapabilities?, String)>[
    (null, 'capabilities_unavailable'),
    (
      const DevicePublishCapabilities(
        microphoneInjection: false,
        cameraInjection: true,
        mediaInjectionTransport: 'direct',
      ),
      'device_capability',
    ),
    (
      const DevicePublishCapabilities(
        microphoneInjection: true,
        cameraInjection: true,
        mediaInjectionTransport: 'other',
      ),
      'device_capability',
    ),
  ]) {
    test('capability guard ${row.$2} precedes capture', () async {
      final other = Harness(
        config: StreamConfig(publishCapabilities: row.$1),
        publishCapture: capture,
      );
      addTearDown(other.session.close);
      await other.connect();
      await expectLater(
        other.session.startPublish(microphone),
        fails('publish_unsupported', detail: row.$2),
      );
      expect(capture.calls, 0);
      expect(other.ws.ofType('publishStart'), isEmpty);
    });
  }
}
