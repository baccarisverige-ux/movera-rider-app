#!/usr/bin/env python3
"""Audit Phase 7: size budget for a Flutter web release build.

Usage: python3 tool/check_web_budget.py build/web --main-raw BYTES --main-gzip BYTES

Fails when main.dart.js (the Dart program every visit downloads before the
first frame) grows past its budget. The budgets in the CI workflow are the
Phase 7 baseline plus about 10 %; raise them on purpose, in the same change
that needs the bytes, never to make a red build green.
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
