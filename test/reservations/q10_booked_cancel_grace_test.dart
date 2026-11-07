import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// S8 (2026-11-07): server #113 (owner Q10 update "Rule B, but free for 5 min
/// after booking", contract 0.18.49 bookedCancel.graceAfterBookingMin = 5)
/// charges NO fee for a booked-ride cancel within 5 minutes of booking.
/// The rider app still shows a fee then.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final pickup = DateTime.utc(2026, 10, 20, 12);
  final now = pickup.subtract(const Duration(minutes: 30));

  test('premium booked 2 min ago, pickup in 30 min: server free, app shows '
      'a fee', () {
    final ride = Reservation(
      reservationId: 'r-premium',
      createdAt: now.subtract(const Duration(minutes: 2)),
      scheduledPickupAt: pickup,
      pickup: const ReservationPlace(label: 'A'),
      destination: const ReservationPlace(label: 'B'),
      categoryId: 'premium',
      categoryName: 'premium',
      categoryImage: '',
      price: 420,
      currency: 'SEK',
      paymentMethod: 'cash',
      status: ReservationStatus.driverAssigned,
    );
    final terms = ReservationController(
      environment: AppEnv.current,
      config: SeedRiderConfigRepository.seed,
    ).cancelTermsFor(ride, now: now);
    // Server riderCancelFee: kind scheduled && now - created_at < 5 min => null.
    expect(terms.fee, isNull, reason: 'app shows ${terms.fee}');
  });
}
