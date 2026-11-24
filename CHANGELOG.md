## 0.1.0 (2026-11-24)

- Device streaming with WebRTC video, credential discovery and reconnection.
- Touch, mouse, hardware keyboard, IME and explicit system-key input.
- Default stream and approval UI with theme tokens and localized labels.
- Task approvals through authenticated backend callbacks.
- Read-only stream statistics and decoded video dimensions and rotation.
- App visibility and connectivity lifecycle integration.
- PNG screenshots with typed failure and timeout errors.
- `onError` failure reasons (`StreamError`); a fresh stream key per connect through `tokenProvider`; static `StreamCredentials.token` is deprecated but still reused on reconnect until the legacy token hard cut.
- Microphone and camera publish: startPublish / stopPublish with publish state and reasons, and a built-in control over the stream when the device supports it.
- Agent skill skills/mobilerun-device-stream for integrating the SDK.
