#!/usr/bin/env sh
# Contract v0.18.154 P16c (contract.json#appUpdate.headers): the app's own version x.y.z from pubspec.yaml, for
# --dart-define=MOVERA_APP_VERSION=... on every Android / iOS build (the minimum-version check and X-App-Version read
# it; a build without it is "dev" and never checked). With a build number: tool/app_version.sh <build>.
set -eu
cd "$(dirname "$0")/.."
version="$(sed -n 's/^version: *//p' pubspec.yaml)"
version="${version%%+*}"
if [ $# -ge 1 ] && [ -n "$1" ]; then printf '%s+%s\n' "$version" "$1"; else printf '%s\n' "$version"; fi
