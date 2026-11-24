// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/core/publish_transport.dart';
import 'package:mobilerun_flutter/src/webrtc/flutter_webrtc_peer.dart';
import 'package:mobilerun_flutter/src/webrtc/flutter_publish_capture.dart';

import 'support/harness.dart' show pump;
import 'publish_test.dart' show publishCapabilities, camera, microphone, fails;

const audioCodec = {
  'mimeType': 'audio/opus',
  'clockRate': 48000,
  'channels': 2,
};
const videoCodec = {
  'mimeType': 'video/H264',
  'clockRate': 90000,
  'sdpFmtpLine':
      'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f',
};
Map<String, Object?> track(String kind) => {
  'id': '$kind-track',
  'label': kind,
  'kind': kind,
  'enabled': true,
};
const parameters = {
  'encodings': <Object>[],
  'headerExtensions': <Object>[],
  'codecs': <Object>[],
  'rtcp': {'reducedSize': true},
};
Map<String, Object?> transceiver(
  int index,
  String kind,
  String direction, {
  bool local = false,
}) => {
  'transceiverId': 't$index',
  'direction': direction,
  'mid': local ? '$index' : '',
  'sender': {
    'senderId': 's$index',
    'track': <String, Object?>{},
    'ownsTrack': false,
    'rtpParameters': parameters,
  },
  'receiver': {
    'receiverId': 'r$index',
    'track': track(kind),
    'rtpParameters': parameters,
  },
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('FlutterWebRTC.Method');
  late List<MethodCall> calls;
  late List<Map<String, Object?>> transceivers;
  bool ssrc = true;
  bool senderQueryFails = false;
  String? captureError;
  bool cancelled = false;
  Completer<void>? cameraGate;
  setUp(() {
    calls = [];
    transceivers = [];
    ssrc = true;
    senderQueryFails = false;
    captureError = null;
    cancelled = false;
    cameraGate = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC.Event'),
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('FlutterWebRTC/peerConnectionEventpc'),
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      final args = call.arguments as Map? ?? {};
      switch (call.method) {
        case 'createPeerConnection':
          return {'peerConnectionId': 'pc'};
        case 'addTransceiver':
          final kind = args['mediaType'] as String;
          final init = args['transceiverInit'] as Map;
          final result = transceiver(
            transceivers.length,
            kind,
            init['direction'] as String,
          );
          transceivers.add(result);
          return result;
        case 'getRtpSenderCapabilities':
          if (senderQueryFails) throw PlatformException(code: 'unsupported');
          return {
            'codecs': [args['kind'] == 'audio' ? audioCodec : videoCodec],
            'headerExtensions': [],
            'fecMechanisms': [],
          };
        case 'getRtpReceiverCapabilities':
          return {
            'codecs': [videoCodec],
            'headerExtensions': [],
            'fecMechanisms': [],
          };
        case 'createDataChannel':
          return {
            'id': (args['dataChannelDict'] as Map)['id'],
            'flutterId': args['label'],
          };
        case 'createOffer':
          return {
            'type': 'offer',
            'sdp':
                'v=0\r\n'
                'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:0\r\na=recvonly\r\n'
                'm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:1\r\na=recvonly\r\n'
                'm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:2\r\na=sendonly\r\na=rtpmap:96 H264/90000\r\na=fmtp:96 packetization-mode=1;profile-level-id=42e01f\r\n${ssrc ? "a=ssrc:22 cname:upstream\r\n" : ""}'
                'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=mid:3\r\na=sendonly\r\na=rtpmap:111 opus/48000/2\r\n${ssrc ? "a=ssrc:33 cname:upstream\r\n" : ""}',
          };
        case 'getTransceivers':
          return {
            'transceivers': [
              for (var i = 0; i < transceivers.length; i++)
                {...transceivers[i], 'mid': '$i'},
            ],
          };
        case 'rtpTransceiverGetCurrentDirection':
          return {'result': 'sendonly'};
        case 'getUserMedia':
          final constraints = args['constraints'] as Map;
          if (captureError != null && constraints['video'] != false) {
            throw PlatformException(
              code: 'DOMException',
              message: captureError,
            );
          }
          final audio = constraints['audio'] != false;
          if (!audio) await cameraGate?.future;
          return {
            'streamId': audio ? 'microphone' : 'camera',
            'audioTracks': audio ? [track('audio')] : [],
            'videoTracks': audio ? [] : [track('video')],
          };
        default:
          return null;
      }
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  test('first offer reserves downstream audio/video then upstream video/audio without capture', () async {
    final peer = await FlutterWebRtcPeerFactory().create(
      {},
      config: const StreamConfig(publishCapabilities: publishCapabilities),
      muted: true,
    );
    addTearDown(peer.close);
    await peer.createLocalOffer();
    final additions = calls
        .where((call) => call.method == 'addTransceiver')
        .map((call) => call.arguments as Map)
        .toList();
    expect(additions.map((args) => args['mediaType']), [
      'audio',
      'video',
      'video',
      'audio',
    ]);
    expect(
      additions.map((args) => (args['transceiverInit'] as Map)['direction']),
      ['recvonly', 'recvonly', 'sendonly', 'sendonly'],
    );
    expect(additions.any((args) => args.containsKey('trackId')), isFalse);
    expect(calls.where((call) => call.method == 'getUserMedia'), isEmpty);
    expect((peer as PublishPeerTransport).publishKinds, {
      PublishKind.audio,
      PublishKind.video,
    });
    expect(
      await (peer as PublishPeerTransport).canAttachPublish([
        PublishKind.audio,
        PublishKind.video,
      ]),
      isTrue,
    );
  });

  test(
    'missing trackless SSRC disables publish while preserving viewer offer',
    () async {
      ssrc = false;
      final peer = await FlutterWebRtcPeerFactory().create(
        {},
        config: const StreamConfig(publishCapabilities: publishCapabilities),
        muted: true,
      );
      addTearDown(peer.close);
      expect(await peer.createLocalOffer(), startsWith('v=0'));
      expect((peer as PublishPeerTransport).publishKinds, isEmpty);
    },
  );

  test(
    'unsupported sender capability API leaves downstream viewing available',
    () async {
      senderQueryFails = true;
      final peer = await FlutterWebRtcPeerFactory().create(
        {},
        config: const StreamConfig(publishCapabilities: publishCapabilities),
        muted: true,
      );
      addTearDown(peer.close);
      await peer.createLocalOffer();
      expect(transceivers, hasLength(2));
      expect((peer as PublishPeerTransport).publishKinds, isEmpty);
    },
  );

  test('receive-only config adds no upstream sections and never queries sender codecs', () async {
    final peer = await FlutterWebRtcPeerFactory().create(
      {},
      config: const StreamConfig(),
      muted: true,
    );
    addTearDown(peer.close);
    await peer.createLocalOffer();
    expect(transceivers, hasLength(2));
    expect(
      calls.where((call) => call.method == 'getRtpSenderCapabilities'),
      isEmpty,
    );
  });

  test('plugin camera permission denial stops microphone and maps actual flattened exception', () async {
    captureError = 'NotAllowedError';
    await expectLater(
      const FlutterPublishCapture().capture(
        camera,
        isCancelled: () => cancelled,
        onAcquired: (_) {},
      ),
      fails('permission_denied', detail: 'capture_permission'),
    );
    expect(
      calls
          .where((call) => call.method == 'trackDispose')
          .map((call) => call.arguments),
      [
        {'trackId': 'audio-track'},
      ],
    );
    expect(
      calls
          .where((call) => call.method == 'streamDispose')
          .map((call) => call.arguments),
      [
        {'streamId': 'microphone'},
      ],
    );
  });

  test(
    'plugin unavailable camera is a capture failure and releases microphone',
    () async {
      captureError = 'NotFoundError';
      await expectLater(
        const FlutterPublishCapture().capture(
          camera,
          isCancelled: () => cancelled,
          onAcquired: (_) {},
        ),
        fails('publish_failed', detail: 'capture_unavailable'),
      );
      expect(
        calls.where((call) => call.method == 'trackDispose'),
        hasLength(1),
      );
    },
  );

  test(
    'microphone capture never asks for camera and stop is idempotent',
    () async {
      final media = await const FlutterPublishCapture().capture(
        microphone,
        isCancelled: () => cancelled,
        onAcquired: (_) {},
      );
      final constraints =
          (calls.singleWhere((call) => call.method == 'getUserMedia').arguments
                  as Map)['constraints']
              as Map;
      expect(constraints['video'], false);
      expect(constraints['audio'], {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      });
      await media.stop();
      await media.stop();
      expect(
        calls.where((call) => call.method == 'trackDispose'),
        hasLength(1),
      );
    },
  );

  test(
    'stop during camera prompt releases acquired mic and late camera',
    () async {
      cameraGate = Completer<void>();
      late PublishMedia owned;
      final capture = const FlutterPublishCapture().capture(
        camera,
        isCancelled: () => cancelled,
        onAcquired: (media) => owned = media,
      );
      await pump();
      expect(
        calls.where((call) => call.method == 'getUserMedia'),
        hasLength(2),
      );
      cancelled = true;
      await owned.stop();
      expect(
        calls
            .where((call) => call.method == 'trackDispose')
            .map((call) => call.arguments),
        [
          {'trackId': 'audio-track'},
        ],
      );
      cameraGate!.complete();
      await capture;
      expect(
        calls
            .where((call) => call.method == 'trackDispose')
            .map((call) => call.arguments),
        [
          {'trackId': 'audio-track'},
          {'trackId': 'video-track'},
        ],
      );
    },
  );

  test(
    'cancelled permission result releases mic and never starts a camera prompt',
    () async {
      cancelled = true;
      await const FlutterPublishCapture().capture(
        camera,
        isCancelled: () => cancelled,
        onAcquired: (_) {},
      );
      expect(
        calls.where((call) => call.method == 'getUserMedia'),
        hasLength(1),
      );
      expect(
        calls.where((call) => call.method == 'trackDispose'),
        hasLength(1),
      );
    },
  );
}
