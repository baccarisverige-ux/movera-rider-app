#!/usr/bin/env python3
"""File-size ratchet (Rule 25: no hand-written source file over 1,500 lines).

Owner decision Q45c (2026-11-09), global plan step 54b / U19. Plain Python 3,
no dependencies, so every CI runner can run it.

How it works
  * Every file in SCOPE (hand-written source only; generated files and data
    such as *.g.dart, *.freezed.dart, *.arb, lib/l10n/generated/, app_localizations*.dart are excluded) must be <= `limit` lines.
  * Files that were already over the limit when the ratchet was introduced are
    listed in `size-ratchet.json` next to this script ("over": {path: lines}).
    Such a file may only SHRINK: it must stay <= its stored count.
  * The check FAILS (exit 1) when a tracked file grew above its stored count,
    or when any other file crosses the limit.
  * When a tracked file shrank (or dropped under the limit) the check PASSES
    but prints a hint: run `--update` so the baseline is tightened in the same
    PR (convention: a PR that shrinks a file also commits the new baseline).

Usage
  python3 tool/size_ratchet.py             check (CI step "File size ratchet (Rule 25)")
  python3 tool/size_ratchet.py --update    rewrite size-ratchet.json from the tree
  python3 tool/size_ratchet.py --self-test prove the check on a temp tree (grow -> fail)
"""
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
BASELINE = os.path.join(HERE, "size-ratchet.json")
LIMIT = 1500
# (directory under the repo root, accepted extensions); "" ext = every file.
SCOPE = [("lib", (".dart",)), ("test", (".dart",))]
SINGLE_FILES = []
EXCLUDE_DIRS = {"node_modules", "build", ".dart_tool", "contracts", ".git",
                "__pycache__", "generated", "dist", "coverage"}
EXCLUDE_SUFFIXES = (".g.dart", ".freezed.dart", ".arb")
# `flutter gen-l10n` output (lib/l10n/app_localizations*.dart) is generated too.
EXCLUDE_PREFIXES = ("app_localizations",)


def count_lines(path):
    with open(path, "rb") as fh:
        data = fh.read()
    return data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0)


def scoped_files(root):
    out = []
    for sub, exts in SCOPE:
        top = os.path.join(root, sub)
        for dirpath, dirnames, filenames in os.walk(top):
            dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDE_DIRS)
            for name in sorted(filenames):
                if name.endswith(EXCLUDE_SUFFIXES) or name.startswith(EXCLUDE_PREFIXES):
                    continue
                if exts and not name.endswith(exts):
                    continue
                out.append(os.path.relpath(os.path.join(dirpath, name), root))
    for name in SINGLE_FILES:
        if os.path.isfile(os.path.join(root, name)):
            out.append(name)
    return sorted(set(p.replace(os.sep, "/") for p in out))


def measure(root):
    return {p: count_lines(os.path.join(root, p)) for p in scoped_files(root)}


def load_baseline(path):
    if not os.path.isfile(path):
        return {"limit": LIMIT, "over": {}}
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def write_baseline(path, counts, limit):
    over = {p: n for p, n in sorted(counts.items()) if n > limit}
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"limit": limit, "over": over}, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return over


def check(root, baseline_path, quiet=False):
    base = load_baseline(baseline_path)
    limit, over = int(base.get("limit", LIMIT)), base.get("over", {})
    counts = measure(root)
    failures, shrunk = [], []
    for path, n in counts.items():
        if path in over:
            if n > over[path]:
                failures.append(f"{path}: {n} lines, grew above its tracked {over[path]}")
            elif n < over[path]:
                shrunk.append(f"{path}: {n} (tracked {over[path]})")
        elif n > limit:
            failures.append(f"{path}: {n} lines, over the {limit}-line limit (Rule 25)")
    gone = [p for p in over if p not in counts]
    if failures:
        if not quiet:
            print("File size ratchet FAILED (Rule 25: files may only shrink):")
            for line in failures:
                print("  " + line)
        return 1
    if not quiet:
        print(f"File size ratchet OK: {len(counts)} files checked, "
              f"{len(over)} files over the limit tracked in {os.path.basename(baseline_path)}")
    if (shrunk or gone) and not quiet:
        for line in shrunk:
            print("  shrank: " + line)
        for p in gone:
            print("  removed: " + p)
        print(f"Hint: tighten the baseline in this PR: python3 {os.path.relpath(__file__, root)} --update")
    return 0


def self_test():
    global SCOPE, SINGLE_FILES
    SCOPE, SINGLE_FILES = [("src", (".txt",))], []
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "src"))
        big = os.path.join(tmp, "src", "big.txt")
        with open(big, "w") as fh:
            fh.write("x\n" * (LIMIT + 5))
        bl = os.path.join(tmp, "size-ratchet.json")
        assert write_baseline(bl, measure(tmp), LIMIT) == {"src/big.txt": LIMIT + 5}
        assert check(tmp, bl, quiet=True) == 0, "tracked file at its count must pass"
        with open(big, "a") as fh:
            fh.write("x\n")
        assert check(tmp, bl, quiet=True) == 1, "a grown tracked file must fail"
        with open(big, "w") as fh:
            fh.write("x\n" * (LIMIT - 1))
        assert check(tmp, bl, quiet=True) == 0, "a shrunk file must pass"
        with open(os.path.join(tmp, "src", "new.txt"), "w") as fh:
            fh.write("y\n" * (LIMIT + 1))
        assert check(tmp, bl, quiet=True) == 1, "a new file over the limit must fail"
    print("self-test OK")
    return 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    if "--update" in sys.argv:
        over = write_baseline(BASELINE, measure(ROOT), LIMIT)
        print(f"baseline written: {len(over)} files over {LIMIT} lines")
        sys.exit(0)
    sys.exit(check(ROOT, BASELINE))
