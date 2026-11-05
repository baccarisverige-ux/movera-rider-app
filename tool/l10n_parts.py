#!/usr/bin/env python3
"""Combines the per-area translation files into the one ARB per language
that Flutter gen-l10n reads.

  lib/l10n/parts/<area>.<lang>.arb  ->  lib/l10n/app_<lang>.arb

New texts go in their area file (see lib/l10n/parts/README.md), never in
lib/l10n/app_<lang>.arb: that file is written by this tool.

  python3 tool/l10n_parts.py          write the ARBs
  python3 tool/l10n_parts.py --check  fail when an ARB differs from its parts

tool/gen_l10n_messages.py runs this first. test/l10n/l10n_parts_test.dart
checks the same in flutter test.
"""
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parent.parent
LANGS = ('en', 'fr', 'sv')
PARTS = root / 'lib/l10n/parts'


def areas():
    return sorted({p.name.split('.')[0] for p in PARTS.glob('*.arb')})


def merged(lang):
    """The ARB text: the inner lines of every area file, areas in name order."""
    bodies = []
    for area in areas():
        text = (PARTS / f'{area}.{lang}.arb').read_text(encoding='utf-8')
        lines = text.rstrip('\n').split('\n')
        assert lines[0] == '{' and lines[-1] == '}', f'{area}.{lang}.arb'
        json.loads(text)
        if len(lines) > 2:
            bodies.append('\n'.join(lines[1:-1]))
    text = '{\n' + ',\n'.join(bodies) + '\n}\n'
    json.loads(text)
    return text


def check_keys():
    """Each area file holds the same messages in every language, and no
    message is in two areas."""
    seen = {}
    for area in areas():
        keys = {}
        for lang in LANGS:
            data = json.loads((PARTS / f'{area}.{lang}.arb').read_text(encoding='utf-8'))
            keys[lang] = {k for k in data if not k.startswith('@')}
        for lang in ('fr', 'sv'):
            if keys[lang] != keys['en']:
                sys.exit(f'{area}.{lang}.arb: missing {sorted(keys["en"] - keys[lang])} '
                         f'extra {sorted(keys[lang] - keys["en"])}')
        for k in keys['en']:
            if k in seen:
                sys.exit(f'{k} is in both {seen[k]} and {area}')
            seen[k] = area


def main():
    check = '--check' in sys.argv[1:]
    check_keys()
    stale = []
    for lang in LANGS:
        path = root / f'lib/l10n/app_{lang}.arb'
        text = merged(lang)
        if check:
            if path.read_text(encoding='utf-8') != text:
                stale.append(str(path.relative_to(root)))
        else:
            path.write_text(text, encoding='utf-8')
    if stale:
        sys.exit(f'{", ".join(stale)} differ from lib/l10n/parts: '
                 'run python3 tool/l10n_parts.py and commit the result.')
    print(f'lib/l10n/app_{{{",".join(LANGS)}}}.arb from {len(areas())} area files')


if __name__ == '__main__':
    main()
