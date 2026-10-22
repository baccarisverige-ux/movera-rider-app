import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/scheduled_ride_terms.dart';

/// rider-u169: the Terms page opened from a Premium reservation stated
/// the single admin rule (free until 1 h, then 50 kr) while the ride is
/// charged by Premium's rule (free until 2 h, then 25 % of the fare).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('the Terms page states the rule the ride is charged by', (
    tester,
  ) async {
    final pickup = DateTime.utc(2026, 10, 22, 5, 15);
    final now = DateTime.utc(2026, 10, 21, 12);
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_premium',
      ),
      clock: () => now,
      config: SeedRiderConfigRepository.seed,
    );
    await c.create(
      ReservationDraft(
        scheduledPickupAt: pickup,
        pickup: const ReservationPlace(label: 'Klockarvägen 37'),
        destination: const ReservationPlace(label: 'Arlanda Express'),
        categoryId: 'premium',
        categoryName: 'Premium',
        categoryImage: 'assets/images/rides/premium.webp',
        price: 600,
        paymentMethod: 'Cash',
      ),
    );
    final terms = c.cancelTermsFor(c.byId('rsv_premium')!);
    // Premium's own rule: 2 h window, 25 % of kr 600.
    expect(terms.window, const Duration(minutes: 120));
    expect(terms.lateFee.amountMinor, 15000);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduledRideTermsPage(
          controller: c,
          reservationId: 'rsv_premium',
        ),
      ),
    );

    final rule = tester.widget<Text>(
      find.byKey(const Key('scheduled-terms-cancel-rule')),
    );
    expect(rule.data, contains(ReservationFormat.window(terms.window)));
    expect(rule.data, contains(ReservationFormat.money(terms.lateFee)));
    expect(rule.data, isNot(contains(ReservationFormat.cancelRule(c.rules))));
  });
}
