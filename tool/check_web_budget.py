#!/usr/bin/env python3
"""Audit Phase 7: size budget for a Flutter web release build.

Usage: python3 tool/check_web_budget.py build/web --main-raw BYTES --main-gzip BYTES

Fails when main.dart.js (the Dart program every visit downloads before the
first frame) grows past its budget. The budgets in the CI workflow are the
Phase 7 baseline plus about 10 %; raise them on purpose, in the same change
that needs the bytes, never to make a red build green.

Raised on purpose 2026-11-22. Reason: launch build: 11 launch sets merged
(SMS sign-in, account deletion, Stripe fee sheet, change the ride, live
location, load cuts, SOS by press time, admin sign-out, booked-ride screens,
minimum app version, real-app address). Rule used (the driver app's,
tool/web_budget.json there): the largest main.dart.js measured over the
builds CI checks + 2 %, rounded up to the next KiB.
  Old budget (Phase 7 baseline + about 10 %): raw 6,500,000, gzip 1,850,000.
  Measured 2026-11-22 (raw / gzip -9):
    ci.yml production build            6,502,531 / 1,852,212
    publish-web-live.yml live  (/live/) 6,502,615 / 1,852,265
    publish-web-live.yml real  (/app/)  6,502,620 / 1,852,269
  (main before the launch sets, same real-app flags: 6,436,525 / 1,834,058.)
  New budget: raw 6,633,472, gzip 1,890,304 (ci.yml and publish-web-live.yml).
"""
import argparse
import gzip
import pathlib
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("build_dir")
    parser.add_argument("--main-raw", type=int, required=True)
    parser.add_argument("--main-gzip", type=int, required=True)
    args = parser.parse_args()
    main_js = pathlib.Path(args.build_dir) / "main.dart.js"
    if not main_js.is_file():
        print(f"missing {main_js}", file=sys.stderr)
        return 1
    data = main_js.read_bytes()
    raw = len(data)
    packed = len(gzip.compress(data, compresslevel=9))
    print(f"main.dart.js: {raw:,} bytes (budget {args.main_raw:,}), gzip -9 {packed:,} bytes (budget {args.main_gzip:,})")
    failed = False
    if raw > args.main_raw:
        print(f"::error::main.dart.js is {raw - args.main_raw:,} bytes over its raw budget", file=sys.stderr)
        failed = True
    if packed > args.main_gzip:
        print(f"::error::main.dart.js is {packed - args.main_gzip:,} bytes over its gzip budget", file=sys.stderr)
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
