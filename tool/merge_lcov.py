#!/usr/bin/env python3
"""Merge the lcov files of the CI test shards into one report.

usage: tool/merge_lcov.py OUT IN [IN ...]

Hits for the same source line are added; LF/LH are recomputed, so the
merged file reads like one `flutter test --coverage` run.
"""
import sys
from collections import defaultdict


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    files = defaultdict(lambda: defaultdict(int))
    for path in argv[2:]:
        current = None
        with open(path, encoding="utf-8") as report:
            for raw in report:
                line = raw.strip()
                if line.startswith("SF:"):
                    current = files[line[3:]]
                elif line.startswith("DA:") and current is not None:
                    number, hits = line[3:].split(",")[:2]
                    current[int(number)] += int(hits)
                elif line == "end_of_record":
                    current = None
    with open(argv[1], "w", encoding="utf-8") as out:
        for source in sorted(files):
            lines = files[source]
            out.write(f"SF:{source}\n")
            for number in sorted(lines):
                out.write(f"DA:{number},{lines[number]}\n")
            out.write(f"LF:{len(lines)}\nLH:{sum(1 for h in lines.values() if h > 0)}\n")
            out.write("end_of_record\n")
    print(f"merged {len(argv) - 2} reports, {len(files)} source files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
