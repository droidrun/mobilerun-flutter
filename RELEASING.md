# Releasing to pub.dev

Nothing has been published yet. Pull requests only validate the package. A `v*`
tag runs the reusable CI workflow without publishing permissions, then requests
approval through the `pub-dev` environment before publishing. The upload job
checks that the commit belongs to `main` and the tag matches the stable package
version. These workflow checks prevent mistakes, not misuse: environment
protection, pub.dev's environment requirement and tag rules are required controls.

## Required one-time setup

The repository owner must complete all of these steps before automated publishing:

1. Create a [verified publisher](https://dart.dev/tools/pub/verified-publishers)
   for `mobilerun.ai`. Verify domain ownership through the DNS record requested
   by Google Search Console and add the intended maintainers.
2. Decide repository visibility and confirm the public repository and issue
   tracker links. Uploaded package source is public regardless of repository
   visibility. Confirm the Apache-2.0 license and example are ready to distribute.
3. Prepare a release PR for `0.1.0`: update the changelog and remove the README's
   pre-release status and "after first release" installation notes, replacing
   them with the released installation instructions. Merge after CI passes.
   From that exact commit, run the checks in [README Development](README.md#development)
   using its pinned Flutter version, then **manually** run `flutter pub publish`.
   Authenticate interactively with the authorized uploader account. New packages
   require this manual first upload; automated publishing cannot create them.
   The package initially belongs to the uploader's account. Transfer it to the
   company publisher on the package Admin settings, then verify publisher ownership.
4. Create the GitHub environment `pub-dev` with a required reviewer and deployment
   restrictions allowing only tags matching `v*`. Enable protection against
   self-approval. The upload job already references this environment.
5. On the package's pub.dev Admin settings, enable automated publishing from
   `droidrun/mobilerun-flutter` with tag pattern `v{{version}}`. Enable **Require
   GitHub Actions environment** and require `pub-dev`.
   See [automated publishing](https://dart.dev/tools/pub/automated-publishing).
   No long-lived publishing secret is needed; OIDC credentials are minted by
   `dart-lang/setup-dart@v1` immediately before the upload.
6. Create an active GitHub tag ruleset for `v*` restricting tag creation, updates
   and deletion to authorized release maintainers. Review workflow changes and
   environment approvals before releasing.

After the manual upload and setup, create the historical `v0.1.0` tag on that
release commit. Reject its `pub-dev` environment approval because `0.1.0` is already published
and versions are immutable. Confirm the existing version on pub.dev; no second
upload is needed.
Subsequent tags publish new versions. No upload, tag, account setup or visibility
change is part of preparing this pipeline.

## Each release

1. At the first tag, update every pre-release sentence:
   - README Installation: replace “Install from source until the first release”
     and “After the first release” with the released installation command.
   - README Quickstart: remove “The package is not published yet and its
     API may still change.”
   - TESTING has no pre-release sentences that need changing.
   - RELEASING introduction: remove “Nothing has been published yet.”
   - RELEASING Required one-time setup: mark completed setup as historical,
     including the manual first upload and historical-tag instructions.
   - CHANGELOG: change “0.1.0 (unreleased)” to the release version and date.

   Set a stable `X.Y.Z` version in `pubspec.yaml`, update `CHANGELOG.md` and the
   README installation example. For public API changes, run
   `dart run tool/api_dump.dart`, inspect and commit the signature diff.
   The contract covers exports of `lib/mobilerun_flutter.dart`, excluding
   `@internal` declarations. Imports from `lib/src/` are implementation details.
2. Run the checks in [README Development](README.md#development). Resolve every
   dry-run warning and inspect the package contents, including `LICENSE`,
   `CHANGELOG.md`, `README.md`, `lib/` and `example/`. CI performs the same checks
   without requesting publishing credentials.
3. Merge only after CI is green. From the merged release commit on `main`,
   create and push the matching tag, for example:

   ```sh
   git tag v0.1.1
   git push origin v0.1.1
   ```

4. After verification succeeds, review the tag and commit before approving the
   `pub-dev` environment deployment. Inspect the publishing Actions run and
   verify the version, publisher, documentation and installation on pub.dev
   before announcing it. Published versions are immutable; diagnose failures
   before retrying.
