import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// rider-u57: the Ride check copy promised "not at a planned stop or in
/// traffic", but nothing in the app or the contract ever says the car is in
/// traffic (RideCheckSample.inTraffic has no producer), so a queue where
/// the car stays within 25 m for longStopMinutes opens the card. The copy
/// now promises only what the check does.
void main() {
  for (final (locale, words) in <(String, List<String>)>[
    ('en', ['in traffic', 'traffic']),
    ('sv', ['kö', 'trafik']),
    ('fr', ['embouteillage', 'trafic']),
  ]) {
    test('$locale long-stop copy does not promise a traffic exemption', () {
      final l10n = lookupAppLocalizations(Locale(locale));
      for (final text in [
        l10n.rcLongStopBody('2'),
        l10n.rcDemoLongStopScenario('2'),
      ]) {
        for (final word in words) {
          expect(text.toLowerCase(), isNot(contains(word)), reason: text);
        }
        // The planned-stop exemption is real and stays.
        expect(
          text.toLowerCase(),
          contains(
            locale == 'en'
                ? 'planned stop'
                : locale == 'sv'
                ? 'planerat stopp'
                : 'arrêt prévu',
          ),
        );
      }
    });
  }
}
