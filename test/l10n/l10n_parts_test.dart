import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// Base split (owner 2026-11-05, rule 25): the rider texts live in one file
// per area, lib/l10n/parts/<area>.<lang>.arb, and tool/l10n_parts.py
// combines them into the one ARB per language that gen-l10n reads.

const _langs = ['en', 'fr', 'sv'];

List<String> _areas() =>
    Directory('lib/l10n/parts')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.arb'))
        .map((name) => name.split('.').first)
        .toSet()
        .toList()
      ..sort();

/// What tool/l10n_parts.py writes: the inner lines of every area file,
/// areas in name order.
String _merged(String lang) {
  final bodies = <String>[];
  for (final area in _areas()) {
    final lines = File(
      'lib/l10n/parts/$area.$lang.arb',
    ).readAsStringSync().trimRight().split('\n');
    if (lines.length > 2) {
      bodies.add(lines.sublist(1, lines.length - 1).join('\n'));
    }
  }
  return '{\n${bodies.join(',\n')}\n}\n';
}

/// Every key and value, key order ignored.
String _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_canonical).join(',')}]';
  return jsonEncode(value);
}

void main() {
  test('each ARB is exactly its area files combined', () {
    for (final lang in _langs) {
      expect(
        File('lib/l10n/app_$lang.arb').readAsStringSync(),
        _merged(lang),
        reason: 'Run python3 tool/gen_l10n_messages.py and commit the result.',
      );
    }
  });

  test('each area holds the same messages in every language, once', () {
    final seen = <String, String>{};
    for (final area in _areas()) {
      Set<String> keys(String lang) =>
          (jsonDecode(File('lib/l10n/parts/$area.$lang.arb').readAsStringSync())
                  as Map<String, dynamic>)
              .keys
              .where((k) => !k.startsWith('@'))
              .toSet();
      for (final lang in _langs) {
        expect(keys(lang), keys('en'), reason: '$area.$lang.arb');
      }
      for (final key in keys('en')) {
        expect(seen[key], isNull, reason: '$key is in ${seen[key]} and $area');
        seen[key] = area;
      }
    }
  });

  test('the split kept every key and value of the ARBs before it', () {
    // sha256 of each ARB's keys and values (key order ignored), taken from
    // the single-file ARBs before the split (base/split-rider-big-3). A later
    // PR that changes a text updates these to the values the failure prints.
    // v0.18.93 (job C9): + waitingPausedDriverAway (autoArrive.texts.riderPaused).
    // BQ-V46 (G7): menuAppVersion drops the "v" ("Movera Rider 1.4.0 (583)").
    // BQ-V41 (wallet history): + 14 texts in the wallet_history area.
    // BQ-V39: + 21 refund choice texts (payments area, contract debtModel.refunds).
    // v0.18.108 (job C9b): + stopWaitingPausedDriverAway
    // (autoArrive.stops.texts.riderStopPaused).
    // BQ-V16: + historyPlannedRoute (past ride on the server's planned route).
    // J10 (debt model): + quoteDebtLine, riderDebtAboveMax, walletFee,
    // walletDebtPaid, walletYouOwe (payments area, contract debtModel.texts).
    // Saved-places design (contract v0.18.129): + 7 places* texts.
    // R4 (2026-11-20): + pinDecidedByArea, pinStatusByArea (ride area).
    // Real SMS sign-in codes (contract v0.18.133 smsSignIn.texts):
    // + errSmsNotSent, errSmsDailyLimit; textFourDigitCode 4 -> 6 (owner
    // 2026-11-20 "Yes, 4 → 6 only (Rec.)").
    // Account deletion E1 (contract v0.18.134): + deleteOpenTrip, accountClosed (account area).
    // v0.18.136 (Stripe rider fee): + 5 fee* card-payment texts.
    // v0.18.143 (change route while searching): + priceChangedTitle,
    // confirmNewPrice (general area).
    // v0.18.144 (live location + adjust-pickup banner): + 7 live* texts
    // (live_location area).
    // v0.18.148 (sosPressTime): + sosNotSent (safety area, owner to confirm).
    // Admin sign-out (contract v0.18.149): + signedOutByMovera (account area).
    // P16c (contract v0.18.154 appUpdate.texts): + minVersionTitle,
    // minVersionBody, minVersionUpdate (app_update area).
    // v0.18.155 driver profile: + 27 texts in the driver_profile area.
    // Owner 2026-11-23: + dpChat (short chat button word, driver_profile).
    // Owner 2026-11-23 (approved search screen): + 8 fd* texts in the
    // searching_screen area (Justera, edit subtitle, share-location sheet).
    // Owner 2026-11-23 (raise card R2): + bumpSubtitle, bumpSliderHint.
    const before = {
      'en': (
        'f1db9f7a356ed9dfd36cf0dd3b516578598b0a90d1b00986cfc158edc9883265',
        2334,
      ),
      'fr': (
        'b87548fa7ea6d6e41d3e1a216d51e93ec0aff419b8f7efd0f81c68379b6052fd',
        1823,
      ),
      'sv': (
        '265f61e7312985ec1fac252094a924866ebb098ad11bfeaba1fd2b19c948c36f',
        1823,
      ),
    };
    for (final lang in _langs) {
      final arb =
          jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
              as Map<String, dynamic>;
      final hash = sha256.convert(utf8.encode(_canonical(arb))).toString();
      expect(arb.length, before[lang]!.$2, reason: lang);
      expect(hash, before[lang]!.$1, reason: '$lang now: $hash');
    }
  });
}
