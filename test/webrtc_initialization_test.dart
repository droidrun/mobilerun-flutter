// Copyright 2026 Mobilerun
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobilerun_flutter/mobilerun_flutter.dart';
import 'package:mobilerun_flutter/src/webrtc/flutter_webrtc_peer.dart';

void main() {
  testWidgets(
    'renderer then peer initialize WebRTC once with zero playout delay',
    (tester) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('FlutterWebRTC.Method');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        switch (call.method) {
          case 'createVideoRenderer':
            return {'textureId': 1};
          case 'createPeerConnection':
            throw PlatformException(code: 'test-peer');
          default:
            return null;
        }
      });
      final session = DeviceStreamSession(credentials: () async => null);
      addTearDown(session.close);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DeviceStreamView(session: session, hasControl: false),
        ),
      );
      await tester.pump();
      await expectLater(
        FlutterWebRtcPeerFactory().create(
          {},
          config: const StreamConfig(),
          muted: true,
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(calls.map((call) => call.method), [
        'initialize',
        'createVideoRenderer',
        'videoRendererSetSrcObject',
        'createPeerConnection',
      ]);
      expect(calls.first.arguments, {
        'options': {'zeroPlayoutDelay': true},
      });
      await tester.pumpWidget(const SizedBox());
    },
  );
}
