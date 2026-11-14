# mobilerun-flutter

Flutter package for embedding Mobilerun device streaming and events.

## Status: pre-release core

Only the headless core exists so far. It is pure Dart, with no WebRTC, network
or UI code:

- `lib/src/protocol/`: protocol constants, the binary control message encoders
  (touch, scroll, hover, keycode, text, set-clipboard) and the typed
  signalling messages.
- `lib/src/core/`: the reconnect controller, a state machine driven through an
  injectable `Scheduler` and clock-free random source.

The core behaves byte for byte and step for step like the `@mobilerun/react`
package. This is checked against the shared conformance fixtures vendored in
`conformance/fixtures` (the pinned tag is in `conformance/VERSION`). The
package is not published yet and its API may still change.

## Development

```sh
flutter pub get
flutter analyze
dart format --set-exit-if-changed .
flutter test
```

Every test is data-driven over the fixture files and named after the fixture
case it checks.

### Updating the fixtures

```sh
tool/sync-conformance.sh TAG PATH_TO_CONFORMANCE_CLONE
dart run tool/generate_constants.dart
```

The first command replaces `conformance/fixtures` with the copy at the given
release tag. The second regenerates `lib/src/protocol/constants.dart` from
`constants.json`. Always pin a tag, never a branch.

## License

Apache-2.0, see `LICENSE`.
