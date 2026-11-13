// Throwaway spike: can flutter_webrtc carry the Mobilerun stream protocol?
//
// Config (incl. the stream token) is read at run time from a file in the app's
// private files dir that a local script writes via `adb run-as`. It is never
// compiled in, never logged and never committed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _configPath = '/data/user/0/ai.mobilerun.spike.stream_spike/files/spike.json';

void log(String m) => print('SPIKE ${DateTime.now().toIso8601String()} $m');

class SpikeConfig {
  SpikeConfig(this.deviceId, this.streamUrl, this.token, this.zpd, this.script);
  final String deviceId, streamUrl, token, script;
  final bool zpd;

  static Future<SpikeConfig> load() async {
    final j = jsonDecode(await File(_configPath).readAsString()) as Map<String, dynamic>;
    return SpikeConfig(
      j['deviceId'] as String,
      j['streamUrl'] as String,
      j['streamToken'] as String,
      (j['zpd'] as bool?) ?? false,
      (j['script'] as String?) ?? '',
    );
  }
}

// Control messages (copied byte-for-byte from the web client).
class Msg {
  static const injectTouch = 2;
  static const actionDown = 0, actionUp = 1, actionMove = 2, actionCancel = 3;

  /// 32 bytes. pointerId is big-endian (the web client's DataView default),
  /// everything else is little-endian.
  static Uint8List touch(int action, int pointerId, int vw, int vh, double x, double y,
      {double pressure = 1.0, int actionButton = 1, int buttons = 1}) {
    final b = ByteData(32);
    var o = 0;
    b.setUint8(o, injectTouch);
    o += 1;
    b.setUint8(o, action);
    o += 1;
    b.setInt64(o, pointerId, Endian.big);
    o += 8;
    b.setInt32(o, x.round(), Endian.little);
    o += 4;
    b.setInt32(o, y.round(), Endian.little);
    o += 4;
    b.setUint16(o, vw, Endian.little);
    o += 2;
    b.setUint16(o, vh, Endian.little);
    o += 2;
    // JS: setInt16(round(pressure * 0xffff)) wraps 65535 -> -1; same two bytes.
    b.setUint16(o, (pressure * 0xffff).round() & 0xffff, Endian.little);
    o += 2;
    b.setInt32(o, actionButton, Endian.little);
    o += 4;
    b.setInt32(o, buttons, Endian.little);
    return b.buffer.asUint8List();
  }
}

class StreamClient {
  StreamClient(this.cfg, this.renderer, this.onState);
  final SpikeConfig cfg;
  final RTCVideoRenderer renderer;
  final void Function() onState;

  final sessionId = _uuid();
  WebSocketChannel? ws;
  RTCPeerConnection? pc;
  RTCDataChannel? control, hover;
  Timer? keepAlive;
  int gen = 0; // bumped on every start/stop; guards stale callbacks
  bool remoteSet = false;
  final pending = <RTCIceCandidate>[];
  final sw = Stopwatch();
  String status = 'idle';
  Completer<int>? firstFrame;
  final marks = <String, int>{};

  static String _uuid() {
    final r = Random.secure();
    String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-a${h(3)}-${h(12)}';
  }

  void mark(String k) {
    marks[k] = sw.elapsedMilliseconds;
    log('t+${sw.elapsedMilliseconds}ms $k');
  }

  Uri _wsUri() {
    final u = Uri.parse(cfg.streamUrl);
    return u.replace(queryParameters: {...u.queryParameters, 'token': cfg.token});
  }

  /// Connects and resolves with ms until the first video frame was rendered.
  Future<int> start() async {
    await stop();
    final g = ++gen;
    bool cur() => g == gen;
    firstFrame = Completer<int>();
    remoteSet = false;
    pending.clear();
    marks.clear();
    sw
      ..reset()
      ..start();
    status = 'connecting';
    onState();

    renderer.onFirstFrameRendered = () {
      if (!cur()) return;
      mark('firstFrameRendered');
      if (!(firstFrame?.isCompleted ?? true)) firstFrame!.complete(sw.elapsedMilliseconds);
    };

    try {
      final channel = IOWebSocketChannel.connect(_wsUri(), connectTimeout: const Duration(seconds: 10));
      ws = channel;
      await channel.ready;
      mark('wsOpen');
      final rtcCfg = Completer<Map<String, dynamic>>();
      channel.stream.listen((raw) {
        if (!cur()) return;
        Map<String, dynamic> m;
        try {
          m = jsonDecode(raw as String) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        if (!rtcCfg.isCompleted && m['type'] == 'rtcConfiguration') {
          rtcCfg.complete(Map<String, dynamic>.from(m['rtcConfiguration'] as Map));
          return;
        }
        _onMessage(g, m);
      }, onDone: () {
        if (!cur()) return;
        log('ws closed code=${channel.closeCode} pcState=${pc?.connectionState}');
        status = 'ws closed';
        onState();
      }, onError: (e) {
        if (!cur()) return;
        log('ws error ${e.runtimeType}');
      });

      _send({'type': 'requestRtcConfiguration', 'sessionId': sessionId, 'supportsLiveRtcRefresh': true});
      final rc = await rtcCfg.future.timeout(const Duration(seconds: 10));
      if (!cur()) return -1;
      mark('rtcConfiguration');

      final conn = await createPeerConnection({...rc, 'sdpSemantics': 'unified-plan'});
      if (!cur()) {
        await conn.close();
        return -1;
      }
      pc = conn;
      await conn.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
      final vt = await conn.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));

      // Same codec order as the web client: VP9, H265, H264, rest.
      try {
        final caps = await getRtpReceiverCapabilities('video');
        final codecs = [...(caps.codecs ?? <RTCRtpCodecCapability>[])];
        int prio(RTCRtpCodecCapability c) {
          final m = c.mimeType.toLowerCase();
          if (m.contains('vp9')) return 1;
          if (m.contains('h265') || m.contains('hevc')) return 2;
          if (m.contains('h264') || m.contains('avc')) return 3;
          return 4;
        }

        codecs.sort((a, b) => prio(a) - prio(b));
        log('receiver codecs (sorted): ${codecs.map((c) => c.mimeType).join(',')}');
        await vt.setCodecPreferences(codecs);
        log('setCodecPreferences ok');
      } catch (e) {
        log('setCodecPreferences failed: $e');
      }

      control = await conn.createDataChannel('control', RTCDataChannelInit()
        ..ordered = true
        ..negotiated = true
        ..id = 1);
      hover = await conn.createDataChannel('hover', RTCDataChannelInit()
        ..ordered = false
        ..maxRetransmits = 0
        ..negotiated = true
        ..id = 2);
      control!.onDataChannelState = (s) {
        if (!cur()) return;
        log('control channel $s');
        if (s == RTCDataChannelState.RTCDataChannelOpen) {
          mark('controlOpen');
          for (var i = 0; i < 12; i++) {
            Future.delayed(Duration(milliseconds: i * 125), () {
              if (cur()) _send({'type': 'requestFrame', 'sessionId': sessionId});
            });
          }
        }
      };
      hover!.onDataChannelState = (s) {
        if (cur()) log('hover channel $s');
      };
      control!.onMessage = (m) {
        if (cur()) log('control rx ${m.isBinary ? 'bin ${m.binary.length}B' : 'text'}');
      };

      conn.onConnectionState = (s) {
        if (!cur()) return;
        log('pc connectionState $s');
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) mark('pcConnected');
        status = s.name.replaceFirst('RTCPeerConnectionState', '');
        onState();
      };
      conn.onIceConnectionState = (s) {
        if (cur()) log('ice state $s');
      };
      conn.onTrack = (e) {
        if (!cur()) return;
        mark('track ${e.track.kind}');
        if (e.track.kind == 'video') {
          renderer.srcObject = e.streams.isNotEmpty ? e.streams[0] : null;
          onState();
        }
      };
      conn.onIceCandidate = (c) {
        if (!cur() || c.candidate == null) return;
        _send({
          'type': 'candidate',
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
          'sessionId': sessionId,
        });
      };

      final offer = await conn.createOffer();
      if (!cur()) return -1;
      log('offer m=video codecs: ${_videoCodecs(offer.sdp!)}');
      await conn.setLocalDescription(offer);
      _send({'type': 'offer', 'sdp': offer.sdp, 'sessionId': sessionId});
      mark('offerSent');

      keepAlive = Timer.periodic(const Duration(seconds: 10), (_) {
        if (cur()) _send({'type': 'keepAlive', 'sessionId': sessionId});
      });

      return await firstFrame!.future.timeout(const Duration(seconds: 30));
    } catch (e) {
      log('start failed: ${e.runtimeType} $e');
      status = 'error';
      onState();
      return -1;
    }
  }

  Future<void> _onMessage(int g, Map<String, dynamic> m) async {
    bool cur() => g == gen;
    final conn = pc;
    switch (m['type']) {
      case 'answer':
        if (conn == null) return;
        try {
          await conn.setRemoteDescription(RTCSessionDescription(m['sdp'] as String, 'answer'));
        } catch (e) {
          log('setRemoteDescription failed: $e');
          return;
        }
        if (!cur()) return;
        mark('answerApplied');
        log('answer m=video codecs: ${_videoCodecs(m['sdp'] as String)}');
        remoteSet = true;
        for (final c in pending) {
          try {
            await conn.addCandidate(c);
          } catch (e) {
            log('buffered candidate failed: $e');
          }
        }
        pending.clear();
        break;
      case 'candidate':
        if (conn == null) return;
        final c = RTCIceCandidate(m['candidate'] as String?, m['sdpMid'] as String?, m['sdpMLineIndex'] as int?);
        if (!remoteSet) {
          pending.add(c);
        } else {
          try {
            await conn.addCandidate(c);
          } catch (e) {
            log('candidate failed: $e');
          }
        }
        break;
      case 'rtcConfiguration':
        // Mid-session TURN credential refresh -> setConfiguration + ICE restart.
        final servers = (m['rtcConfiguration'] as Map?)?['iceServers'];
        if (conn == null || servers == null) return;
        try {
          await conn.setConfiguration({'iceServers': servers});
          log('refresh: setConfiguration ok');
        } catch (e) {
          log('refresh: setConfiguration failed: $e');
          return;
        }
        try {
          final before = (await conn.getLocalDescription())?.sdp;
          final offer = await conn.createOffer({
            'mandatory': {'IceRestart': true, 'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
            'optional': [],
          });
          if (!cur()) return;
          await conn.setLocalDescription(offer);
          remoteSet = false;
          pending.clear();
          _send({'type': 'offer', 'sdp': offer.sdp, 'sessionId': sessionId});
          log('refresh: ICE-restart offer sent, ufrag changed=${_ufrag(before) != _ufrag(offer.sdp)}');
        } catch (e) {
          log('refresh: ICE restart failed: $e');
        }
        break;
      default:
        log('rx unhandled ${m['type']}');
    }
  }

  static String? _ufrag(String? sdp) => RegExp(r'a=ice-ufrag:(\S+)').firstMatch(sdp ?? '')?.group(1);

  static String _videoCodecs(String sdp) {
    final sec = sdp.split('m=').firstWhere((s) => s.startsWith('video'), orElse: () => '');
    return RegExp(r'a=rtpmap:\d+ ([A-Za-z0-9]+)/').allMatches(sec).map((m) => m.group(1)).toSet().join(',');
  }

  void _send(Map<String, dynamic> m) {
    try {
      ws?.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  /// Guarded: never send on a channel that is not open.
  bool sendControl(Uint8List data) {
    final c = control;
    if (c == null || c.state != RTCDataChannelState.RTCDataChannelOpen) return false;
    c.send(RTCDataChannelMessage.fromBinary(data));
    return true;
  }

  /// Simulates a dropped signalling socket; the peer connection is left alone.
  void killWs() {
    log('forcing WS close (peer connection untouched)');
    ws?.sink.close(4000);
  }

  Future<Map<String, dynamic>> stats() async {
    final out = <String, dynamic>{};
    final conn = pc;
    if (conn == null) return out;
    final reports = await conn.getStats();
    String? codecId;
    for (final r in reports) {
      if (r.type == 'inbound-rtp' && (r.values['kind'] ?? r.values['mediaType']) == 'video') {
        codecId = r.values['codecId']?.toString();
        for (final k in [
          'framesDecoded', 'framesReceived', 'framesDropped', 'frameWidth', 'frameHeight',
          'framesPerSecond', 'jitterBufferDelay', 'jitterBufferEmittedCount', 'bytesReceived',
          'packetsLost', 'decoderImplementation', 'totalDecodeTime',
        ]) {
          if (r.values[k] != null) out[k] = r.values[k];
        }
      }
    }
    for (final r in reports) {
      if (r.type == 'codec' && r.id == codecId) {
        out['codec'] = r.values['mimeType'];
        out['fmtp'] = r.values['sdpFmtpLine'];
      }
      if (r.type == 'candidate-pair' && r.values['state'] == 'succeeded' && r.values['nominated'] == true) {
        out['rtt'] = r.values['currentRoundTripTime'];
      }
    }
    return out;
  }

  Future<void> stop() async {
    gen++;
    keepAlive?.cancel();
    keepAlive = null;
    try {
      await ws?.sink.close();
    } catch (_) {}
    ws = null;
    try {
      await control?.close();
      await hover?.close();
    } catch (_) {}
    control = hover = null;
    renderer.srcObject = null;
    try {
      await pc?.close();
    } catch (_) {}
    pc = null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cfg = await SpikeConfig.load();
  // Field trials are process global: must be set before the first peer connection.
  await WebRTC.initialize(options: cfg.zpd ? {'zeroPlayoutDelay': true} : {});
  log('init zeroPlayoutDelay=${cfg.zpd} script=${cfg.script}');
  runApp(SpikeApp(cfg));
}

class SpikeApp extends StatelessWidget {
  const SpikeApp(this.cfg, {super.key});
  final SpikeConfig cfg;
  @override
  Widget build(BuildContext context) =>
      MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark(), home: SpikePage(cfg));
}

class SpikePage extends StatefulWidget {
  const SpikePage(this.cfg, {super.key});
  final SpikeConfig cfg;
  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final renderer = RTCVideoRenderer();
  late final StreamClient client;
  final _videoKey = GlobalKey();
  final _pointers = <int, int>{}; // flutter pointer -> protocol pointerId

  @override
  void initState() {
    super.initState();
    client = StreamClient(widget.cfg, renderer, () {
      if (mounted) setState(() {});
    });
    renderer.initialize().then((_) {
      renderer.onResize = () {
        log('video size ${renderer.videoWidth}x${renderer.videoHeight}');
        if (mounted) setState(() {});
      };
      _autorun();
    });
  }

  Future<void> _autorun() async {
    final s = widget.cfg.script;
    if (s.isEmpty) return;
    if (s == 'ttff') {
      for (var i = 1; i <= 3; i++) {
        final ms = await client.start();
        await Future.delayed(const Duration(seconds: 4));
        log('RESULT ttff run=$i ms=$ms marks=${client.marks} stats=${await client.stats()}');
        await client.stop();
        await Future.delayed(const Duration(seconds: 2));
      }
      log('RESULT ttff done');
    } else if (s == 'session') {
      final ms = await client.start();
      log('RESULT session first frame ms=$ms marks=${client.marks}');
      for (var i = 0; i < 4; i++) {
        await Future.delayed(const Duration(seconds: 5));
        log('RESULT stats ${await client.stats()}');
      }
    }
  }

  @override
  void dispose() {
    client.stop();
    renderer.dispose();
    super.dispose();
  }

  /// Letterbox mapping (object-fit: contain) into video pixel space.
  ({double x, double y})? _toVideo(Offset p, Size box) {
    final vw = renderer.videoWidth, vh = renderer.videoHeight;
    if (vw == 0 || vh == 0) return null;
    final va = vw / vh, ca = box.width / box.height;
    var aw = box.width, ah = box.height;
    if (va > ca) {
      ah = box.width / va;
    } else {
      aw = box.height * va;
    }
    final ox = (box.width - aw) / 2, oy = (box.height - ah) / 2;
    final rx = p.dx - ox, ry = p.dy - oy;
    if (rx < 0 || rx > aw || ry < 0 || ry > ah) return null;
    return (x: (rx / aw * vw).clamp(0, vw).toDouble(), y: (ry / ah * vh).clamp(0, vh).toDouble());
  }

  void _touch(PointerEvent e, int action, Size box) {
    final vw = renderer.videoWidth, vh = renderer.videoHeight;
    int? pid;
    ({double x, double y})? pos;
    if (action == Msg.actionDown) {
      pos = _toVideo(e.localPosition, box);
      if (pos == null) return;
      pid = _pointers.length; // 0-based like touch.identifier
      _pointers[e.pointer] = pid;
    } else {
      pid = _pointers[e.pointer];
      if (pid == null) return;
      pos = _toVideo(e.localPosition, box);
      if (pos == null) {
        // Outside: React reuses the last position; the spike just skips moves.
        if (action == Msg.actionMove) return;
        pos = (x: 0.0, y: 0.0);
      }
      if (action == Msg.actionUp || action == Msg.actionCancel) _pointers.remove(e.pointer);
    }
    final ok = client.sendControl(Msg.touch(action, pid, vw, vh, pos.x, pos.y));
    log('touch action=$action pid=$pid video=(${pos.x.round()},${pos.y.round()}) of ${vw}x$vh sent=$ok');
  }

  Future<void> _stats() async {
    final s = await client.stats();
    log('RESULT stats $s');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text('${client.status}  ${renderer.videoWidth}x${renderer.videoHeight}',
                style: const TextStyle(fontSize: 11)),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final box = Size(c.maxWidth, c.maxHeight);
              return Listener(
                key: _videoKey,
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _touch(e, Msg.actionDown, box),
                onPointerMove: (e) => _touch(e, Msg.actionMove, box),
                onPointerUp: (e) => _touch(e, Msg.actionUp, box),
                onPointerCancel: (e) => _touch(e, Msg.actionCancel, box),
                child: RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
              );
            }),
          ),
          Wrap(spacing: 4, children: [
            TextButton(onPressed: () async => log('RESULT connect ms=${await client.start()}'), child: const Text('Connect')),
            TextButton(onPressed: client.killWs, child: const Text('KillWS')),
            TextButton(
                onPressed: () => client._send({'type': 'requestRtcConfiguration', 'sessionId': client.sessionId, 'supportsLiveRtcRefresh': true}),
                child: const Text('Refresh')),
            TextButton(onPressed: _stats, child: const Text('Stats')),
          ]),
        ]),
      ),
    );
  }
}
