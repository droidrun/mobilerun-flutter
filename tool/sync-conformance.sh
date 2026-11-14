#!/usr/bin/env bash
# Refresh the vendored conformance fixtures from a clone of the shared
# conformance repository.
#
# Usage: tool/sync-conformance.sh TAG CONFORMANCE_CLONE_PATH
#
# Example: tool/sync-conformance.sh v0.1.0 ../mobilerun-sdk-conformance
#
# The copy lives in conformance/fixtures and the pinned tag is recorded in
# conformance/VERSION. Never track a branch: always pass a release tag.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 TAG CONFORMANCE_CLONE_PATH" >&2
  exit 2
fi

tag="$1"
clone="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"

git -C "$clone" fetch --tags --quiet
git -C "$clone" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null || {
  echo "unknown tag: $tag" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$clone" archive "$tag" fixtures | tar -x -C "$tmp"

rm -rf "$root/conformance/fixtures"
mkdir -p "$root/conformance"
mv "$tmp/fixtures" "$root/conformance/fixtures"
printf '%s\n' "$tag" > "$root/conformance/VERSION"
echo "conformance fixtures now at $tag"
