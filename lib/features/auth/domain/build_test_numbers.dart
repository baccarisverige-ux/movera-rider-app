/// Owner 2026-11-03: test builds get the test numbers at build time
/// (`--dart-define=MOVERA_TEST_NUMBERS=+46...,+33...`, filled from the
/// GitHub Actions secret MOVERA_TEST_NUMBERS by the live-test deploy). Numbers
/// only, never names; store/production builds are never given it. Anything
/// that is not an E.164 number is ignored.
const String _buildTestNumbers = String.fromEnvironment('MOVERA_TEST_NUMBERS');

final RegExp _e164 = RegExp(r'^\+[1-9]\d{6,14}$');

List<String> parseTestNumbers([String raw = _buildTestNumbers]) => [
  for (final part in raw.split(RegExp(r'[\s,;]+')))
    if (_e164.hasMatch(part)) part,
];
