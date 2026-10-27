#!/usr/bin/env python3
"""Audit Phase 7: memory budget over repeated bookings on the web build.

Usage: python3 tool/check_memory_budget.py probe.json

Reads the output of tool/web_lifecycle_probe.mjs (cancel mode) and checks
Home after each booking, from the second booking on (the first one loads
the Maps script, the pool and the caches once):

- JS heap after GC grows at most HEAP_MB_PER_BOOKING a booking on average,
- JS event listeners grow at most LISTENERS_TOTAL over the run,
- the map layer created at most MAPS_CREATED google.maps.Map objects,
- no WebGL context was lost.

Baseline (docs/audit/phase-7.md, 10 bookings, Chromium, Safari's
rasterizer): heap 40.8 -> 48.5 MB from booking 1 to 10 (0.86 MB a
booking; the early bookings grow most: 1.30 MB a booking over bookings
2-5 of a 5-booking run), listeners 470 -> 478, 2 maps created, 0 contexts
lost. The budget leaves room for a slower runner's GC. Before the
Phase 6 map pool the same run grew about 4 MB, 870 listeners and 5 maps a
booking, which is what this check is for.
"""
import json
import sys

HEAP_MB_PER_BOOKING = 2.0
LISTENERS_TOTAL = 40
MAPS_CREATED = 2


def main() -> int:
    data = json.load(open(sys.argv[1]))
    homes = [r for r in data["rows"] if r["label"] == "home"]
    if len(homes) < 4:
        print(f"::error::need at least 3 bookings, got {len(homes) - 1}", file=sys.stderr)
        return 1
    start, end = homes[1], homes[-1]
    bookings = end["cycle"] - start["cycle"]
    per_booking = (end["jsHeapUsedMB"] - start["jsHeapUsedMB"]) / bookings
    listeners = end["listeners"] - start["listeners"]
    created = (end.get("layerStats") or {}).get("created")
    lost = data["summary"]["contextsLost"]
    print(f"heap {start['jsHeapUsedMB']} -> {end['jsHeapUsedMB']} MB over {bookings} bookings ({per_booking:.2f} MB a booking, budget {HEAP_MB_PER_BOOKING})")
    print(f"listeners {start['listeners']} -> {end['listeners']} (+{listeners}, budget {LISTENERS_TOTAL}); maps created {created} (budget {MAPS_CREATED}); WebGL contexts lost {lost}")
    errors = []
    if per_booking > HEAP_MB_PER_BOOKING:
        errors.append("JS heap grows too fast per booking")
    if listeners > LISTENERS_TOTAL:
        errors.append("event listeners pile up across bookings")
    if created is None or created > MAPS_CREATED:
        errors.append("more google.maps.Map objects than the pool allows")
    if lost:
        errors.append("a WebGL context was lost")
    for e in errors:
        print(f"::error::{e}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
