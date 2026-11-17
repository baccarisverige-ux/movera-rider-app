import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// R-UI UI-10: the same ride read "kr 659" in History and the menu wallet
/// but "659 kr" on Waiting and the route change sheet. Every kronor helper
/// now prints the app's one money format ([formatMoney]: amount, then "kr").
///
/// Price format (owner 2026-11-14: "make sure rider and driver app show
/// correct prices every where", then "Check all apps"): this file used to
/// pin formatKr(100.4) == '100 kr' (rounded to the krona). The owner has
/// overruled that: every amount uses its currency's decimals (SEK and EUR 2
/// with a comma, TND 3 with a dot), whole amounts keep them ("35,00 kr",
/// "5.000 DT"), and the rider never sees an amount rounded to whole kronor.
void main() {
  test('formatKr is exact to the öre and puts kr after the amount', () {
    expect(formatKr(522.0), '522,00 kr'); // reservation price
    expect(formatKr(0), '0,00 kr'); // wallet balance at zero
    expect(formatKr(149.0), '149,00 kr'); // support ride price
    expect(formatKr(100.4), '100,40 kr');
    expect(formatKr(100.5), '100,50 kr');
    expect(formatKr(659), '659,00 kr');
    expect(formatKr(-25), '-25,00 kr');
  });

  test('formatSek (minor units) prints the same exact format', () {
    expect(formatSek(10200), '102,00 kr');
    expect(formatSek(10250), '102,50 kr');
    expect(formatSek(65900), formatMoney(const Money(65900)));
  });

  test('no helper prints the old "kr X" order', () {
    for (final text in [formatKr(659), formatSek(65900)]) {
      expect(text, isNot(startsWith('kr ')));
    }
  });

  // Contract v0.18.59 §81 (owner 2026-11-10): the dinar is written with a
  // dot, 3 decimals, a space between thousands; SEK and EUR keep the comma.
  test('TND with a dot: 12.350 DT, 1 250.000 DT', () {
    expect(formatMoney(const Money(12350, 'TND')), '12.350 DT');
    expect(formatMoney(const Money(1250000, 'TND')), '1 250.000 DT');
    expect(formatMoney(const Money(40, 'TND')), '0.040 DT');
    expect(formatMoney(const Money(-12350, 'TND')), '-12.350 DT');
    expect(formatMoney(const Money(12675)), '126,75 kr');
    expect(formatMoney(const Money(741, 'EUR')), '7,41 €');
  });

  group('whole amounts keep their decimals (owner 2026-11-14)', () {
    test('SEK', () {
      expect(formatMoney(const Money(3500)), '35,00 kr');
      expect(formatMoney(const Money(65900)), '659,00 kr');
      expect(formatMoney(const Money(0)), '0,00 kr');
      expect(formatMoney(const Money(125000)), '1 250,00 kr');
    });
    test('EUR', () {
      expect(formatMoney(const Money(3500, 'EUR')), '35,00 €');
      expect(formatMajor(5, 'EUR'), '5,00 €');
      expect(formatMoney(const Money(125050, 'EUR')), '1 250,50 €');
    });
    test('TND', () {
      expect(formatMoney(const Money(5000, 'TND')), '5.000 DT');
      expect(formatMajor(5, 'TND'), '5.000 DT');
    });
  });

  group('nothing rounds to whole units any more', () {
    test('SEK: formatMoney is exact', () {
      expect(formatMoney(const Money(7410)), '74,10 kr');
      expect(formatMoney(const Money(25950)), '259,50 kr');
    });
    test('formatMajor is exact in every currency', () {
      expect(formatMajor(259.5, 'SEK'), '259,50 kr');
      expect(formatMajor(12.26, 'SEK'), '12,26 kr');
      expect(formatMajor(7.41, 'EUR'), '7,41 €');
      expect(formatMajor(12.35, 'TND'), '12.350 DT');
    });
  });
}
