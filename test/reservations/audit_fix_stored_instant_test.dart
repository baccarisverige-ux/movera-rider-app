import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

/// rider-j8-5: pickup, creation and drop-off times were saved as local ISO
/// strings with no offset, so a device time-zone change before the next
/// launch moved the booked pickup instant. They are saved as UTC instants
/// (WireTime) now.
void main() {
  final ride = Reservation(
    reservationId: 'rsv_instant',
    createdAt: DateTime(2026, 10, 21, 18, 4),
    scheduledPickupAt: DateTime(2026, 10, 22, 10),
    estimatedDropoffAt: DateTime(2026, 10, 22, 10, 31),
    pickup: const ReservationPlace(label: 'Home'),
    destination: const ReservationPlace(label: 'Work'),
    categoryId: 'economy',
    categoryName: 'Movera',
    categoryImage: 'assets/images/rides/movera.webp',
    price: 300,
    paymentMethod: 'Apple Pay',
    status: ReservationStatus.scheduled,
  );

  test('times are stored with their UTC offset', () {
    final json = ride.toJson();
    for (final key in [
      'createdAt',
      'scheduledPickupAt',
      'estimatedDropoffAt',
    ]) {
      final value = json[key] as String;
      expect(value, endsWith('Z'), reason: key);
    }
  });

  test('a stored ride reads back at the same instants and local times', () {
    final back = Reservation.tryParse(ride.toJson())!;
    expect(
      back.scheduledPickupAt.isAtSameMomentAs(ride.scheduledPickupAt),
      isTrue,
    );
    expect(back.createdAt.isAtSameMomentAs(ride.createdAt), isTrue);
    expect(
      back.estimatedDropoffAt!.isAtSameMomentAs(ride.estimatedDropoffAt!),
      isTrue,
    );
    // Read back on the same device it shows the same clock time.
    expect(back.scheduledPickupAt.hour, 10);
    expect(back.scheduledPickupAt.isUtc, isFalse);
  });
}
