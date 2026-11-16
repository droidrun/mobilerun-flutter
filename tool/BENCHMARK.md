# Stream benchmark

Use exclusive emulator access and an existing test device with Settings in the
launcher's first column near the bottom, matching the input test layout.
Supply a runtime JSON file with `streamUrl` and `streamToken`; the script copies
it into private app storage and removes it on exit. Credentials are never built
into the APK.

```sh
export ANDROID_HOME=PATH_TO_ANDROID_SDK
export AVD=YOUR_EXISTING_AVD
tool/benchmark.sh CREDENTIALS_JSON OUT_DIR
```

Five fresh connections each collect ten fresh one-second steady samples with
bitrate available. FPS, bitrate and RTT are arithmetic means. Ten Settings taps
per connection produce two separate latency measurements: a ~64×64 upright-video
pixel region around the tap, and a central app-launch region (20–80% width,
20–60% height). GPU snapshots crop the rendered video at quarter video resolution.
Both detect a maximum 4×4-tile mean absolute luma difference of at least 4;
the tap region must first remain below 1 over four successive snapshots.
Medians average the two middle samples; p90 uses nearest rank. Snapshot/readback
overhead makes these observed upper bounds. TTFF uses the attempt's monotonic
clock and at most 50 ms between first-frame polls.

Results and phone/tablet screenshots go into `OUT_DIR`, outside the package.
The same runner verifies navigation/text, socket rebuild, unavailable/retry,
fake approval/refetch, background/foreground, emulator network loss/return and
a ten-minute memory soak. It records sampled interruptions and requires automatic
recovery with fresh video within 60 seconds of detection. End RSS growth must
stay within 64 MiB; process RSS and native memory snapshots are recorded.
Session close must clear video/stats. No cloud devices are created or deleted.
