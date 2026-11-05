# Rider translations, one file per area

Rule (owner 2026-11-05, rule 25 "Split everything first"): **new texts go in
their area file**, `lib/l10n/parts/<area>.<lang>.arb`, in all three languages
(en, fr, sv), with the English `@key` description next to the English text.
Never edit `lib/l10n/app_<lang>.arb`: Flutter gen-l10n needs one ARB per
language, so `tool/l10n_parts.py` writes it from the area files.

After a change run `python3 tool/gen_l10n_messages.py` (it combines the area
files first, then writes `test/l10n/all_messages.g.dart`) and commit the
result. CI (`python3 tool/l10n_parts.py --check`) and
`test/l10n/l10n_parts_test.dart` fail when an ARB differs from its parts.

Areas: app, account, cancel, general, legal, payments, reservations, ride,
ride_check, safety, saved_places, search, status_words (written by
`tool/gen_status_words.py`), support. Pick the area of the screen the text is
on; `general` is for texts shared by many screens. A new area is a new
`<area>.en.arb`, `<area>.fr.arb` and `<area>.sv.arb` with the same keys.
