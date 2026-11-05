#!/usr/bin/env bash
# Checks that contracts/ is an exact copy of the shared contract
# (baccarisverige-ux/movera-contracts, branch main). Changes nothing.
#
#  1. every file listed in contracts/CHECKSUMS matches its sha256, and
#     contracts/ holds no other files (no hand edits, nothing missing);
#  2. contracts/CHECKSUMS equals CHECKSUMS of a movera-contracts main commit
#     whose contract.json has the version this copy claims.
#
# Step 2 needs the contract repo (private). It is read from, in order:
#   CONTRACTS_DIR   a local clone of movera-contracts (e.g. ../movera-contracts)
#   CONTRACTS_TOKEN a GitHub token with read access to movera-contracts (CI secret)
# With neither, step 2 is skipped with a warning (step 1 still fails on drift).
#
# usage: <this script>        (from anywhere inside the repo)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
sync_cmd="$(basename "$here")/sync_contract.sh"
dir="$root/contracts"
repo="baccarisverige-ux/movera-contracts"

note() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::$1::$2"; else echo "$1: $2"; fi; }
how_to_sync() {
  echo
  echo "How to sync: from the repo root run"
  echo "  $sync_cmd ${1:-<movera-contracts main commit sha>}"
  echo "then commit the whole contracts/ folder as it comes out. Never edit contracts/ by hand:"
  echo "change movera-contracts first (scripts/checksums.sh), merge it, then sync."
}
fail() { note error "contract copy: $1"; how_to_sync "${2:-}"; exit 1; }

[ -f "$dir/CHECKSUMS" ] || fail "contracts/CHECKSUMS is missing"
[ -f "$dir/contract.json" ] || fail "contracts/contract.json is missing"

# 1. integrity of the copy against its own CHECKSUMS
if ! bad="$(cd "$dir" && sha256sum -c --quiet CHECKSUMS 2>&1)"; then
  echo "$bad"
  fail "files in contracts/ differ from contracts/CHECKSUMS (listed above)"
fi
extra="$(cd "$dir" && find . -type f ! -name CHECKSUMS | sed 's|^\./||' | LC_ALL=C sort \
  | comm -23 - <(awk '{print $2}' CHECKSUMS | LC_ALL=C sort))"
if [ -n "$extra" ]; then
  echo "$extra"
  fail "contracts/ holds files that CHECKSUMS does not list (above)"
fi
version="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$dir/contract.json")"
echo "contract copy: $(wc -l < "$dir/CHECKSUMS") files match contracts/CHECKSUMS (claims version $version)"

# 2. compare with movera-contracts main
tmp=""
trap '[ -n "$tmp" ] && rm -rf "$tmp"' EXIT
if [ -n "${CONTRACTS_DIR:-}" ]; then
  src="$(cd "$CONTRACTS_DIR" && pwd)"
  git -C "$src" fetch -q origin main 2>/dev/null || note warning "could not fetch $src; using its current origin/main"
  main="origin/main"
  git -C "$src" rev-parse -q --verify "$main" >/dev/null || main="HEAD"
elif [ -n "${CONTRACTS_TOKEN:-}" ]; then
  tmp="$(mktemp -d)"; src="$tmp/c"
  git -c credential.helper= clone -q --filter=blob:none --no-checkout --single-branch --branch main \
    "https://x-access-token:${CONTRACTS_TOKEN}@github.com/$repo.git" "$src" 2>/dev/null \
    || fail "could not read $repo with CONTRACTS_TOKEN (token missing access?)"
  main="HEAD"
else
  note warning "contract copy: not compared with $repo main (no CONTRACTS_DIR / CONTRACTS_TOKEN). Add a read-only CONTRACTS_TOKEN secret to enable this."
  exit 0
fi

ours="$(sha256sum < "$dir/CHECKSUMS")"
head_sha="$(git -C "$src" rev-parse "$main")"
head_version="$(git -C "$src" show "$main:contract.json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])')"
match=""
for c in $(git -C "$src" rev-list "$main" -- CHECKSUMS); do
  if [ "$(git -C "$src" show "$c:CHECKSUMS" | sha256sum)" = "$ours" ]; then match="$c"; break; fi
done
if [ -z "$match" ]; then
  fail "contracts/ (claims $version) matches no commit on $repo main (main is $head_version at ${head_sha:0:7})" "$head_sha"
fi
match_version="$(git -C "$src" show "$match:contract.json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])')"
[ "$match_version" = "$version" ] || fail "contracts/ equals $repo ${match:0:7} ($match_version) but contract.json claims $version" "$head_sha"
echo "contract copy: identical to $repo ${match:0:7} (version $version)"
if [ "$(git -C "$src" show "$main:CHECKSUMS" | sha256sum)" != "$ours" ]; then
  note warning "contract copy is behind $repo main ($version here, $head_version on main ${head_sha:0:7}). Sync with: $sync_cmd $head_sha"
fi
