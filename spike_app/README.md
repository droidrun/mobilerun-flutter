# stream_spike

Throwaway spike: can `flutter_webrtc` run the Mobilerun stream protocol on Android?

One sample app (`lib/main.dart`): signalling over `web_socket_channel`, recvonly audio/video transceivers,
negotiated data channels `control` (id 1) and `hover` (id 2), 32-byte touch messages, ICE restart on a
mid-session `rtcConfiguration`, letterbox mapping of taps into video pixel space.

Run-time config (never committed): the app reads `files/spike.json` from its private app dir with
`deviceId`, `streamUrl`, `streamToken`, `zpd` (bool) and `script` (`ttff` | `session` | empty).
`tool/lib.sh` `write_config` writes it through `adb run-as` from a credentials JSON you pass in.

Scripts under `tool/` need `ANDROID_HOME`, `JAVA_HOME` (JDK 17) and `flutter` on `PATH`:
`build_debug.sh`, `session.sh CREDS OUT` (boots an AVD, runs all measurements), `size.sh OUT` (release arm64 size
against a stock app), `explore.sh`.
