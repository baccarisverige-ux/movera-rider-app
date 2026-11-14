import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// Price format (owner 2026-11-14: "make sure rider and driver app show
/// correct prices every where", "Check all apps"; audit
/// price-display-2026-11-14 gaps 9 and 10): one trip shows one exact number
/// on every screen. SEK and EUR with 2 decimals and a comma, TND with 3 and
/// a dot; whole amounts keep their decimals; nothing is rounded to whole
/// kronor (the receipt already showed öre while History, the booked list and
/// the payment line showed whole kronor).
void main() {
  setUpAll(() => L10n.use('en'));

  group('the booked list and History (ReservationFormat)', () {
    test('SEK to the öre', () {
      expect(ReservationFormat.kr(259.5), '259,50 kr');
      expect(ReservationFormat.kr(659), '659,00 kr');
    });
    test('EUR to the cent', () {
      expect(ReservationFormat.kr(12.5, 'EUR'), '12,50 €');
      expect(ReservationFormat.kr(12, 'EUR'), '12,00 €');
    });
    test('TND to the millime', () {
      expect(ReservationFormat.kr(12.35, 'TND'), '12.350 DT');
      expect(ReservationFormat.kr(5, 'TND'), '5.000 DT');
    });
  });

  group('a booked ride price change reads the exact difference', () {
    test('SEK: 40 öre is a change, shown as 0,40 kr', () {
      const change = ReservationPriceChange(previous: 259.1, next: 259.5);
      expect(change.unchanged, isFalse);
      expect(change.summary, contains('0,40 kr'));
    });
    test('EUR and TND', () {
      expect(
        const ReservationPriceChange(
          previous: 10,
          next: 12,
          currency: 'EUR',
        ).summary,
        contains('2,00 €'),
      );
      expect(
        const ReservationPriceChange(
          previous: 10,
          next: 12.35,
          currency: 'TND',
        ).summary,
        contains('2.350 DT'),
      );
    });
  });

  group('the payment line on Finding and Waiting', () {
    test('SEK card only: 259,50 kr, not 260 kr', () {
      expect(
        bookedPaymentLine(paymentMethod: 'Visa •••• 4242', priceKr: 259.5),
        'Visa •••• 4242 · 259,50 kr',
      );
    });
    test('SEK with the wallet: the parts to the öre', () {
      final line = bookedPaymentLine(
        paymentMethod: 'Visa',
        priceKr: 259.5,
        walletMinor: 5025,
      );
      expect(line, contains('209,25 kr'));
      expect(line, contains('50,25 kr'));
    });
    test('EUR and TND whole amounts keep their decimals', () {
      expect(
        bookedPaymentLine(paymentMethod: 'Cash', priceKr: 12, currency: 'EUR'),
        'Cash · 12,00 €',
      );
      expect(
        bookedPaymentLine(paymentMethod: 'Cash', priceKr: 5, currency: 'TND'),
        'Cash · 5.000 DT',
      );
    });
  });

  test('the wallet split labels are exact in SEK too', () {
    final split = WalletSplit.booked(totalMinor: 25950, walletMinor: 10025);
    expect(split.totalLabel, '259,50 kr');
    expect(split.walletLabel, '100,25 kr');
    expect(split.remainderLabel, '159,25 kr');
  });

  test('Select ride, the receipt and History print the same text', () {
    for (final (money, text) in [
      (const Money(25950), '259,50 kr'),
      (const Money(26000), '260,00 kr'),
      (const Money(1250, 'EUR'), '12,50 €'),
      (const Money(12350, 'TND'), '12.350 DT'),
      (const Money(5000, 'TND'), '5.000 DT'),
    ]) {
      final major = money.amountMinor / Money.minorPerMajor(money.currency);
      expect(formatMoney(money), text);
      expect(formatMajor(major, money.currency), text);
      expect(ReservationFormat.kr(major, money.currency), text);
    }
  });
}
