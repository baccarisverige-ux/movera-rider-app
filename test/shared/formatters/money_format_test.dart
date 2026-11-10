import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// R-UI UI-10: the same ride read "kr 659" in History and the menu wallet
/// but "659 kr" on Waiting and the route change sheet. Every kronor helper
/// now prints the app's one money format ([formatMoney]: amount, then "kr").
void main() {
  test('formatKr rounds to the krona and puts kr after the amount', () {
    expect(formatKr(522.0), '522 kr'); // reservation price
    expect(formatKr(0), '0 kr'); // wallet balance at zero
    expect(formatKr(149.0), '149 kr'); // support ride price
    expect(formatKr(100.4), '100 kr');
    expect(formatKr(100.5), '101 kr');
    expect(formatKr(-25), '-25 kr');
  });

  test('formatSek (minor units) prints the same format', () {
    expect(formatSek(10200), '102 kr');
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
}
