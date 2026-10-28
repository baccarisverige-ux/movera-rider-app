import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/status_words.g.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';

/// Contract v0.10.4 §20: the app shows the shared status words
/// (contracts/contract.json#statusWords), never its own. Fails when an ARB
/// word differs from the contract (run tool/gen_status_words.py).
void main() {
  final contract =
      jsonDecode(File('contracts/contract.json').readAsStringSync())
          as Map<String, dynamic>;
  final families =
      (contract['statusWords'] as Map<String, dynamic>)['families']
          as Map<String, dynamic>;

  for (final lang in const ['sv', 'fr', 'en']) {
    test('$lang status words equal contract.json#statusWords', () {
      final l = lookupAppLocalizations(Locale(lang));
      for (final family in statusWordFamilies.keys) {
        final codes = (families[family] as Map<String, dynamic>);
        expect(
          statusWordFamilies[family],
          codes.keys.toList(),
          reason: '$family codes',
        );
        for (final entry in codes.entries) {
          final word = (entry.value as Map<String, dynamic>)[lang];
          expect(
            statusWord(l, family, entry.key),
            word,
            reason: '$lang $family.${entry.key}',
          );
        }
      }
      expect(statusWord(l, 'tripStatus', 'no_such_code'), isNull);
      expect(statusWord(l, 'no_such_family', 'completed'), isNull);
    });
  }

  test('owner words: Slutförd / Terminée, Resenär never Passagerare', () {
    final sv = lookupAppLocalizations(const Locale('sv'));
    final fr = lookupAppLocalizations(const Locale('fr'));
    expect(statusWord(sv, 'tripStatus', 'completed'), 'Slutförd');
    expect(statusWord(fr, 'tripStatus', 'completed'), 'Terminée');
    final svArb = File('lib/l10n/app_sv.arb').readAsStringSync();
    expect(svArb.toLowerCase().contains('passagerare'), isFalse);
  });
}
