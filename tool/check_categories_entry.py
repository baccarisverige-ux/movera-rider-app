"""Owner 2026-11-18 (saved-places design, step 9): the categories screen
opens with ONE transition on every way in. Fails when lib/ builds
SelectRide(, SelectRide.forReturnRide( or PlanReturnRidePage( anywhere but
as the page argument of pushCategories(context, ...). Constructor tear-offs
(SelectRide.new, SelectRide.forReturnRide, PlanReturnRidePage.new) count too.

Usage: python3 tool/check_categories_entry.py [lib]
"""
import pathlib
import re
import sys

DEFINING = {
    'lib/features/ride_selection/presentation/select_ride.dart',
    'lib/features/reservations/presentation/plan_return_ride.dart',
}
OPENER = re.compile(
    r'\b(?:(?:SelectRide|PlanReturnRidePage)(?:\.new)?\('
    r'|(?:SelectRide|PlanReturnRidePage)\.new\b'
    r'|SelectRide\.forReturnRide\b)')
HELPER = re.compile(r'pushCategories(<[^>]*>)?\(\s*context,\s*$')


def offenders(root='lib'):
    base = pathlib.Path(root)
    found = []
    for path in sorted(base.rglob('*.dart')):
        rel = 'lib/' + path.relative_to(base).as_posix()
        if rel in DEFINING:
            continue
        src = path.read_text(encoding='utf-8')
        for m in OPENER.finditer(src):
            line_start = src.rfind('\n', 0, m.start()) + 1
            if src[line_start:m.start()].lstrip().startswith('//'):
                continue
            if not HELPER.search(src[max(0, m.start() - 80):m.start()]):
                found.append(f'{rel}:{src.count(chr(10), 0, m.start()) + 1}')
    return found


if __name__ == '__main__':
    bad = offenders(sys.argv[1] if len(sys.argv) > 1 else 'lib')
    for b in bad:
        print(f'::error::{b}: open the categories screen only with pushCategories()')
    sys.exit(1 if bad else 0)
