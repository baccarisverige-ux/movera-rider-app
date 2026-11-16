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
    // BQ-S10 (v0.18.116): + 9 Share trip sheet texts; shareAutoBody,
    // shareLinkNote and protectSharingBody reworded (no position promised
    // before pickup or near stops).
    const before = {
      'en': (
        '0d31f51875f5ab9a4a2da4e2ddf3a7af05c25ef68d1fddf8961529b723a3ae9b',
        2207,
      ),
      'fr': (
        '8f6696bbb2f78a74b232d71f629a8af3b999a17864321d7b821319d77d71fea5',
        1757,
      ),
      'sv': (
        'a2de645d5625e53c0eed0d9b20f3c3cd51da5c9fb8c161f08a783d72c6f12b02',
        1757,
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
