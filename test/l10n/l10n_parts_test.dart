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
    const before = {
      'en': (
        '595d699881bba1f8c39837eb2d6a30588d243ee3d16de9094e35ff264726ef23',
        2221,
      ),
      'fr': (
        '3f62687c0afa67c84ea5dad9365bc749b2728e5cce3cacfd720999a86a811748',
        1764,
      ),
      'sv': (
        '30189ac4b4c0fb4d8dc1f13d43edf0c2ddebced9e7960bf023cfb06822864958',
        1764,
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
