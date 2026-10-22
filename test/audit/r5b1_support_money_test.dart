import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/l10n/l10n.dart';

void main() {
  test('rider-r5-48: Support shows a charged end-early fare and a cancel fee '
      'to the öre, as History does', () {
    L10n.use('en');
    final ended = SupportRide(
      title: 'Movera',
      when: DateTime.utc(2026, 10, 21, 9),
      price: 35.50,
      image: '',
      endedEarly: true,
    );
    expect(ended.priceLabel, startsWith('35,50 kr'));
    final cancelled = SupportRide(
      title: 'Movera',
      when: DateTime.utc(2026, 10, 21, 9),
      price: 245,
      image: '',
      cancelled: true,
      cancellationFee: 35.50,
    );
    expect(cancelled.priceLabel, contains('35,50 kr'));
  });
}
