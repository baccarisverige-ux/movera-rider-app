import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';

/// Wave 5 R5.6 parts c + d: everything else (low). One test per bug.
void main() {
  test('rider-j8-4: a 0.35 € edit is a real price change', () {
    const change = ReservationPriceChange(
      previous: 12.35,
      next: 12.70,
      currency: 'EUR',
    );
    expect(change.unchanged, isFalse);
    expect(change.summary, contains('0,35 €'));
  });
}
