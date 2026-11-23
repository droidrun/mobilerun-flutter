# Git releases

Version 0.1.0 is distributed from the `v0.1.0` git tag of
`https://github.com/droidrun/mobilerun-flutter.git`. The package lives at the
repository root. No pub.dev upload is needed for this release.

Pull requests and pushes to `main` run CI. The pub.dev workflow in
`.github/workflows/publish.yml` is manual-only (`workflow_dispatch`); pushing a
`v*` tag does not trigger it. Registry publishing is separate from git releases.

## Before the first public tag

The repository owner must confirm the source, history, issue tracker, license
and [third-party notices](THIRD_PARTY_NOTICES.md) are ready for public distribution.
Review repository permissions, fork workflow approvals, private vulnerability
reporting and protection for `main`. Restrict creation, updates and deletion of
`v*` tags to authorized release maintainers.

Repository visibility and tag creation are separate release decisions. Preparing
or merging a release PR does not make the repository public or create a tag.
A public git tag is consumable immediately; a draft GitHub Release is not an
installation gate.

## Each release

1. Prepare a PR against `main`. Set the stable `X.Y.Z` version in `pubspec.yaml`,
   add the matching `## X.Y.Z` heading in `CHANGELOG.md`, and update the README
   dependency ref and version badge. For public API changes, run
   `dart run tool/api_dump.dart`, inspect and commit the signature diff.
   The contract covers exports of `lib/mobilerun_flutter.dart`, excluding
   `@internal` declarations. Imports from `lib/src/` are implementation details.
2. Run the checks in [CONTRIBUTING.md](CONTRIBUTING.md#development) with Flutter
   3.47.9 and its bundled Dart 3.13.7. Also run the example tests and the example
   APK builds from `.github/workflows/ci.yml`. The package dry run validates
   packaging only; it does not upload. Inspect the source, license, notices,
   changelog, README and example intended for distribution.
3. Merge only after CI is green. With explicit release approval, confirm the
   repository is public and create the matching tag on the selected, merged
   release commit on `main`. For 0.1.0:

   ```sh
   git tag v0.1.0 <release-commit>
   git push origin v0.1.0
   ```

   Do not move or overwrite a released tag; fixes need a new version.
4. Verify anonymous source/tag access, then resolve this dependency in a fresh
   Flutter app with `flutter pub get`:

   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     mobilerun_flutter:
       git:
         url: https://github.com/droidrun/mobilerun-flutter.git
         ref: v0.1.0
   ```

   Import `package:mobilerun_flutter/mobilerun_flutter.dart` and follow the
   [host requirements](README.md#install). A GitHub Release may accompany the
   tag, but Flutter resolves the tag without one. Announce only after this
   install check succeeds.
