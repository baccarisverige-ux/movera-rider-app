#!/usr/bin/env sh
# Copies the Movera shared contract (baccarisverige-ux/movera-contracts) at
# a tag or commit into contracts/: only the files its CHECKSUMS lists, plus
# CHECKSUMS. usage: tool/sync_contract.sh v0.4.4
set -eu
ref="${1:?usage: $0 <tag or commit, e.g. v0.4.4>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp"
git -C "$tmp" remote add origin https://github.com/baccarisverige-ux/movera-contracts
git -C "$tmp" fetch -q --depth 1 origin "$ref"
git -C "$tmp" checkout -q FETCH_HEAD
"$tmp/scripts/sync.sh" "$root"
