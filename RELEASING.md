# Releasing to pub.dev

Nothing has been published yet. Pull requests only validate the package; they
cannot publish. A `v*` tag publishes only when its commit belongs to `main` and
its name exactly matches the stable version in `pubspec.yaml`.

## One-time setup

The repository owner must complete these steps before automated publishing:

1. Create a [verified publisher](https://dart.dev/tools/pub/verified-publishers)
   for the company domain, `mobilerun.ai`. Verify domain ownership through the
   DNS record requested by Google Search Console. Add the intended maintainers.
2. Decide repository visibility and confirm that the repository, issue tracker
   and homepage links are suitable for public package users. Publishing a package
   makes its uploaded source public regardless of repository visibility. Ensure
   the Apache-2.0 license and example are ready for distribution.
3. Merge the first release version (`0.1.0`) and its changelog after CI passes.
   From that exact commit, using Flutter 3.47.9, run the checks below, then
   **manually** run `flutter pub publish`. Authenticate interactively with an
   authorized account. New packages require a manual first upload; automated
   publishing cannot create them. Select the company publisher when offered;
   otherwise transfer the newly created package to that publisher from its
   Admin page before continuing. Verify publisher ownership on pub.dev.
4. On the package's pub.dev Admin page, enable automated publishing from
   `droidrun/mobilerun-flutter` with tag pattern `v{{version}}`.
   See [automated publishing](https://dart.dev/tools/pub/automated-publishing).
   No long-lived publishing secret is needed: `dart-lang/setup-dart@v1`
   configures GitHub OIDC authentication and only the tag job can request it.
5. Optionally configure a protected GitHub environment with required approval
   and release-tag restrictions. Add that environment to the `publish` job in
   `.github/workflows/publish.yml` and configure the matching environment on
   pub.dev before using it. Protect release tags and review workflow changes.

Do not push a first-release tag after the manual upload: it would try to publish
that immutable version again. Tags automate subsequent versions only. No upload,
tag, account setup or visibility change is part of preparing this pipeline.

## Each release

1. Set a stable `X.Y.Z` version in `pubspec.yaml`, update `CHANGELOG.md` and the
   README installation example. For public API changes, run
   `dart run tool/api_dump.dart`, inspect the signature diff and commit it.
   The contract covers the exports of `lib/mobilerun_flutter.dart`; imports
   from `lib/src/` are implementation details.
2. With Flutter 3.47.9, run:

   ```sh
   flutter pub get
   flutter pub get --directory example
   flutter analyze
   dart format --set-exit-if-changed .
   flutter test
   dart run tool/api_dump.dart --check
   flutter pub publish --dry-run
   ```

   Resolve every dry-run warning. Inspect the listed package contents, including
   `LICENSE`, `CHANGELOG.md`, `README.md`, `lib/` and `example/`. CI checks the
   same package and public API without requesting publishing credentials.
3. Merge the release PR only after CI is green. From the merged release commit
   on `main`, create and push the matching tag, for example for the next release:

   ```sh
   git tag v0.1.1
   git push origin v0.1.1
   ```

4. Inspect the publishing Actions run, then verify the version, publisher,
   documentation and installation on pub.dev before announcing it. The tag job
   repeats analysis, API verification, tests and the package dry run before
   uploading. Published versions are immutable; diagnose failures before retrying.
