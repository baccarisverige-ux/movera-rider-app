import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/l10n/l10n.dart';

import 'all_messages.g.dart';

/// Round 4 (Q48/Q49): English, French and Swedish carry the same messages.
///
/// Read through gen-l10n's generated classes, not the ARB files: gen-l10n
/// fills a message a language lacks with the English text, so a missing
/// translation shows up as a French or Swedish message equal to English.
/// [allMessages] lists every message of AppLocalizations and does not
/// compile when one is missing (see tool/gen_l10n_messages.py).
void main() {
  final en = allMessages(lookupAppLocalizations(const Locale('en')));

  /// Messages that are the same word in that language (names, units and
  /// loanwords). Everything else must be translated.
  const sameAsEnglish = <String, Set<String>>{
    'fr': {
      'appTitle', 'menu', 'menuNotifications', 'menuBusiness',
      'placeRestaurant', 'destination', 'message', 'total', 'promotion',
      'homeCo2Kg', 'perMinRate', 'menuAppVersion', 'destinationLabel',
      'minLineBreak', 'durMin', 'durH', 'durHMin', 'notification',
      'enterYourCodeAccent', 'date',
      // Round 4 finish: names and words French shares with English.
      'rideCheckTitle', 'safetyContactsCount', 'rcHeadAccident',
      'supportMessages', 'polPromotionsTitle',
    },
    'sv': {
      'appTitle', 'menuSupport', 'menuBusiness', 'placeGym', 'destination',
      'homeCo2Kg', 'perMinRate', 'menuAppVersion', 'destinationLabel',
      'minLineBreak', 'genderMan', 'durMin', 'durH', 'durHMin',
      // Round 4 finish: names and words Swedish shares with English.
      'rideCheckTitle', 'relationshipPartner', 'supportEmailSubject',
    },
  };

  test('the app ships English, French and Swedish only', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      {'en', 'fr', 'sv'},
    );
    expect(L10n.codes, {'en', 'fr', 'sv'});
  });

  for (final code in ['fr', 'sv']) {
    group('$code has every English message', () {
      final other = allMessages(lookupAppLocalizations(Locale(code)));

      test('the same keys, none empty', () {
        expect(other.keys.toSet(), en.keys.toSet());
        for (final e in other.entries) {
          expect(e.value.trim(), isNotEmpty, reason: '$code ${e.key}');
        }
      });

      test('each message is translated (no English fallback)', () {
        final untranslated = [
          for (final key in en.keys)
            if (other[key] == en[key] &&
                !sameAsEnglish[code]!.contains(key))
              key,
        ];
        expect(untranslated, isEmpty, reason: '$code falls back to English');
      });

      test('each placeholder survives translation', () {
        for (final MapEntry(:key, value: names) in messagePlaceholders.entries) {
          for (final name in names) {
            expect(
              other[key],
              contains('<$name>'),
              reason: '$code $key lost {$name}',
            );
          }
        }
        // rider-u236: counts too (rendered as 37, a plural's `other`).
        for (final MapEntry(:key, value: names) in messageCounts.entries) {
          expect(
            other[key],
            contains('37'),
            reason: '$code $key lost {${names.join(', ')}}',
          );
        }
      });

      test('each count message is translated for one as well', () {
        // A plural's `=1` branch is only rendered with 1.
        final enOne = allMessagesWithOne(
          lookupAppLocalizations(const Locale('en')),
        );
        final otherOne = allMessagesWithOne(lookupAppLocalizations(Locale(code)));
        expect(otherOne.keys.toSet(), messageCounts.keys.toSet());
        for (final key in otherOne.keys) {
          expect(otherOne[key]!.trim(), isNotEmpty, reason: '$code $key (1)');
          if (sameAsEnglish[code]!.contains(key)) continue;
          expect(
            otherOne[key],
            isNot(enOne[key]),
            reason: '$code $key (1) falls back to English',
          );
        }
      });
    });
  }
}
