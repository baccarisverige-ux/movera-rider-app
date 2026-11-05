import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
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

  test('owner Q3 + Q5: TripProjection.chain reaches the event; a queued trip '
      'and a late chained one cancel free (fail-before: not read)', () {
    final event = RideRealtimeEvent(
      tripId: 'trp_1',
      status: RideStatus.driverAssigned,
      sequence: 1,
      payload: const {
        chainKey: {'queued': true, 'freeCancelAt': '2026-11-05T12:10:00Z'},
      },
    );
    expect(event.chainQueued, isTrue);
    expect(event.chainFreeCancelAt, DateTime.utc(2026, 11, 5, 12, 10));
    final now = DateTime.utc(2026, 11, 5, 12);
    bool free(bool queued, DateTime? at, DateTime when) =>
        DriverTrackingController.chainCancelFreeAt(queued, at, when);
    expect(free(true, null, now), isTrue);
    final at = DateTime.utc(2026, 11, 5, 12, 10);
    expect(free(false, at, now), isFalse);
    expect(free(false, at, now.add(const Duration(minutes: 11))), isTrue);
  });
}
