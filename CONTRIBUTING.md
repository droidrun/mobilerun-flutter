# Contributing

See [TESTING.md](TESTING.md) to launch the interactive sample and try every feature.
It covers toolchain setup, automated checks and known limitations.

## Development

Use Flutter 3.47.9 (including its bundled Dart SDK).
See [RELEASING.md](RELEASING.md) for publisher setup and release steps.

```sh
flutter pub get
flutter pub get --directory example
flutter analyze
dart format --set-exit-if-changed .
flutter test
dart run tool/api_dump.dart --check
flutter pub publish --dry-run
```

Protocol tests use the shared fixtures. Input tests cover geometry, pointer
slots, scroll, key routing, IME composition and widget-level event routing.

### Updating the fixtures (maintainers)

```sh
tool/sync-conformance.sh TAG PATH_TO_CONFORMANCE_CLONE
dart run tool/generate_constants.dart
dart run tool/generate_key_codes.dart
```

The first command replaces `conformance/fixtures` with the copy at the given
release tag. The second regenerates `lib/src/protocol/constants.dart` from
`constants.json`; the third regenerates keyboard mappings. Always pin a tag, never a branch.

## Pull requests

Use commit messages in the form `type(scope): message` and open pull requests
against `main`. Describe the change and the checks you ran.
Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
