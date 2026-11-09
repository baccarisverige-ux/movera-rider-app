import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract v0.18.53 §75 (owner 2026-11-09): the Ride updates switch stops
/// only "driver found" and "almost there". Its texts must say what always
/// comes: arrived, cancelled, a new driver, no driver, support answers.
void main() {
  Map<String, dynamic> arb(String lang) =>
      jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
          as Map<String, dynamic>;

  const alwaysSent = {
    'en': ['rrived', 'ancelled', 'new driver', 'o driver', 'upport'],
    'sv': ['ramme', 'vbokad', 'ny förare', 'ngen förare', 'upport'],
    'fr': ['rrivé', 'nnulée', 'nouveau chauffeur', 'ucun chauffeur', 'upport'],
  };

  for (final lang in alwaysSent.keys) {
    test('$lang: rideUpdatesBody and pushRideUpdatesOff name what always '
        'comes', () {
      final texts = arb(lang);
      for (final key in ['rideUpdatesBody', 'pushRideUpdatesOff']) {
        final text = texts[key] as String;
        for (final word in alwaysSent[lang]!) {
          expect(text, contains(word), reason: '$lang $key: $word');
        }
      }
    });
  }
}
