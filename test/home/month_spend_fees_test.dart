import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_journey_section.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

/// rider-r5-15: what ended-early trips and cancel fees cost is part of the
/// month's money total.
void main() {
  Reservation ride(String id, ReservationStatus status) => Reservation(
    reservationId: id,
    createdAt: DateTime(2026, 10, 1),
    scheduledPickupAt: DateTime(2026, 10, 3, 8),
    pickup: const ReservationPlace(label: 'A'),
    destination: const ReservationPlace(label: 'B'),
    categoryId: 'economy',
    categoryName: 'Economy',
    categoryImage: 'assets/images/rides/movera.webp',
    price: 259,
    currency: 'SEK',
    paymentMethod: 'Cash',
    status: status,
  );

  test('charged fares and cancel fees count as spent', () {
    final stats = MonthRideStats.fromRides([
      ride('a', ReservationStatus.completed),
      ride(
        'b',
        ReservationStatus.cancelled,
      ).copyWith(endedEarly: true, chargedFare: const Money(12000)),
      ride(
        'c',
        ReservationStatus.cancelled,
      ).copyWith(cancellationFee: const Money(3500)),
      ride('d', ReservationStatus.cancelled),
    ], DateTime(2026, 10, 14, 12));
    expect(stats.pillText, '1 ride · 414 kr');
  });
}
