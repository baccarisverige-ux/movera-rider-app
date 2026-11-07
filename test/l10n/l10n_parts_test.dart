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
    const before = {
      'en': (
        '8d0c9b37ca6e971bbace95bc9ae172a2691b1e90091240a7ca1e7e0a363238c1',
        2074,
      ),
      'fr': (
        'efe42db05d914b7a45cc5c42f394c96cd86af29ecb7eae999e552ba812a1a223',
        1690,
      ),
      'sv': (
        '989cf2d4d4c2e991311c0d7521265aa1638cd33e73dfc0389d07db112119d0b4',
        1690,
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
