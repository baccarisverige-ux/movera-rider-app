import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';

/// Fix job 5 (contract v0.18.33, `contract.json#afterTestRules`).
void main() {
  Map<String, dynamic> body({required bool walletFirst}) =>
      BookingCoordinator.contractTripBody(
        quoteId: 'q_1',
        categoryId: 'economy',
        paymentMethod: 'cash',
        pickupLat: 59.33,
        pickupLng: 18.06,
        destinationLat: 59.32,
        destinationLng: 18.07,
        walletFirst: walletFirst,
      );

  test('owner Q6: the per-ride wallet switch is always sent; off says false '
      '(fail-before: left out, so the server default on used the wallet)', () {
    expect(body(walletFirst: true)['walletFirst'], isTrue);
    expect(body(walletFirst: false)['walletFirst'], isFalse);
    expect(body(walletFirst: false).containsKey('walletFirst'), isTrue);
  });

  test('owner Q6: a booked ride starts with the wallet on', () {
    final draft = ReservationDraft(
      scheduledPickupAt: DateTime.utc(2026, 11, 6, 9),
      pickup: const ReservationPlace(label: 'Sergels torg'),
      destination: const ReservationPlace(label: 'Medborgarplatsen'),
      categoryId: 'economy',
      categoryName: 'Economy',
      categoryImage: '',
      price: 312,
      paymentMethod: 'Cash',
    );
    expect(draft.walletFirst, isTrue);
  });
}
