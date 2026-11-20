← [README](../README.md) · [Partner guide](https://docs.mobilerun.ai/partners)

# Stream statistics

`session.stats` is a read-only `ValueListenable<StreamStats?>`. Samples are
published once per second only while the session is connected, visible, and
has listeners; the value is null otherwise, including after close. Suppressed
ICE restart dips follow the session's connected state.

```dart
session.stats.addListener(() {
  final stats = session.stats.value;
  if (stats == null) return;
  print('${stats.fps} fps, ${stats.bitrateKbps} Kbit/s, ${stats.rttMs} ms RTT');
});
```

`StreamStats` is an immutable, SDK-created value. Optional fields include video
dimensions, codec, bitrate, selected ICE pair RTT, separate local/remote candidate
types, lost packets, dropped frames, freezes, jitter-buffer/decode duration per
frame, and time to the first observed decoded frame. Unsupported values and the
first counter-derived rates remain null. Rates use one-second publishing ticks;
size-only polls do not advance their baselines. First-frame timing uses the
attempt's monotonic clock with a 50 ms polling interval until the first frame.
Value equality lets the notifier deduplicate unchanged samples.

See [the benchmark procedure](../tool/BENCHMARK.md) for rendered tap-region and
app-launch latency measurements, steady rates, and lifecycle/memory checks.
