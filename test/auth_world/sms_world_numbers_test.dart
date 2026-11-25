import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';

/// Contract v0.18.157 (contract.json#smsSignIn.otherCountries; owner
/// 2026-11-24 "ALL numbers must be able to log in in the RIDER app, all
/// kinds of numbers from all countries"): the phone field offers every
/// country (flag + dial code) and takes a free "+" number of any country;
/// the server decides, the app never refuses a valid foreign number.
void main() {
  final contract =
      jsonDecode(File('contracts/contract.json').readAsStringSync()) as Map;
  final other =
      (contract['smsSignIn'] as Map)['otherCountries'] as Map<String, dynamic>;

  test('the contract copy has the other-countries rule, on for the rider', () {
    final defaults =
        (contract['configDefaults'] as Map)['smsSignInOtherCountries'] as Map;
    expect(defaults['enabled'], isTrue);
    expect(other['apps'], contains('any country'));
  });

  test('every inhabited dial code can be picked, each with a flag', () {
    final dials = PhoneCountries.all.map((c) => c.dial).toSet();
    for (final dial in [
      '1',
      '7',
      '20',
      '27',
      '44',
      '49',
      '61',
      '81',
      '86',
      '91',
      '212',
      '213',
      '216',
      '234',
      '351',
      '358',
      '880',
      '971',
      '972',
      '998',
    ]) {
      expect(dials, contains(dial), reason: '+$dial');
    }
    expect(PhoneCountries.all.length, greaterThanOrEqualTo(240));
    for (final c in PhoneCountries.all) {
      expect(c.flag.runes.length, 2, reason: c.iso);
    }
  });

  test('a free "+" number of any country is taken as E.164', () {
    final se = PhoneCountries.sweden;
    final table = <(String, String?)>[
      ('+216 20 123 456', '+21620123456'), // Tunisia
      ('+49 151 1234 5678', '+4915112345678'), // Germany
      ('+1 202 555 0123', '+12025550123'), // USA
      ('+44 7700 900123', '+447700900123'), // UK
      ('+86 138 1234 5678', '+8613812345678'), // China
      ('+212 6 12 34 56 78', '+212612345678'), // Morocco
      ('+49 12', null), // too short
      ('+', null),
    ];
    for (final (typed, expected) in table) {
      expect(phoneNumberFromField(typed, se), expected, reason: typed);
    }
  });
}
