import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';

/// G31 phone run 2 logcat: `GET /rider/trips?kind=scheduled&limit=100` 200,
/// then `reservation.refresh_failed {error: _TypeError}` (also at 04:59:15
/// and 04:59:25, right after sign-in). The server's driver summary on a
/// trip carries `vehicle` as an OBJECT (movera-server
/// src/dispatch/runtime/answers.ts and src/reservations/service.ts:
/// `vehicle: { vehicleId, make, model, color, plate, categoryId }`, shown
/// to the rider by src/trips/projection.ts:232), but
/// `ReservationDriver.tryParse` read it as `map['vehicle'] as String?`.
/// One booked ride with a driver threw, so the whole Upcoming list (and
/// the Home chrono) failed to load. Not from B1.34: that change
/// (d8a8731) touches no field of this answer.
void main() {
  Map<String, dynamic> bookedWithDriver() => {
    'tripId': 'trp_booked_1',
    'kind': 'scheduled',
    'status': 'driver_to_pickup',
    'categoryId': 'economy',
    'paymentMethod': 'cash',
    'scheduledAt': '2026-11-14T08:00:00.000Z',
    'createdAt': '2026-11-13T08:00:00.000Z',
    'fare': {'amountMinor': 25900, 'currency': 'SEK'},
    'pickup': {'address': 'Sergels torg 1', 'lat': 59.3326, 'lng': 18.0649},
    'dropoff': {'address': 'Odenplan 2', 'lat': 59.3426, 'lng': 18.0498},
    'driver': {
      'driverId': 'drv_1',
      'firstName': 'Ali',
      'rating': 4.9,
      'vehicle': {
        'vehicleId': 'veh_1',
        'make': 'Toyota',
        'model': 'Prius',
        'color': 'White',
        'plate': 'ABC123',
        'categoryId': 'economy',
      },
    },
  };

  test('a booked ride whose driver has a vehicle object is read, with the '
      'car, its colour and plate', () {
    final r = ApiReservationRepository.reservationOfTrip(bookedWithDriver());
    expect(r.reservationId, 'trp_booked_1');
    expect(r.driver?.firstName, 'Ali');
    expect(r.driver?.id, 'drv_1');
    expect(r.driver?.vehicle, 'Toyota Prius');
    expect(r.driver?.vehicleColor, 'White');
    expect(r.driver?.plate, 'ABC123');
  });

  test('an empty vehicle object (driver without a car row) is no car', () {
    final trip = bookedWithDriver();
    (trip['driver'] as Map<String, dynamic>)['vehicle'] = <String, dynamic>{};
    final r = ApiReservationRepository.reservationOfTrip(trip);
    expect(r.driver?.firstName, 'Ali');
    expect(r.driver?.vehicle, isNull);
    expect(r.driver?.plate, isNull);
  });

  test('the older flat shape (vehicle text) still reads', () {
    final d = ReservationDriver.tryParse({
      'firstName': 'Sara',
      'vehicle': 'Volvo XC60',
      'vehicleColor': 'Black',
      'plate': 'XYZ789',
    });
    expect(d?.vehicle, 'Volvo XC60');
    expect(d?.vehicleColor, 'Black');
    expect(d?.plate, 'XYZ789');
  });
}
