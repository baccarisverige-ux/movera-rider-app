import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';

/// Phase 134: upcoming_reservation.dart's Cancel/Edit/Plan-return actions had
/// no in-flight guard, so a rapid double-tap on Cancel could issue two
/// concurrent store mutations against the same reservation. Reproduces by
/// double-tapping Cancel reservation and asserting only one confirmation
/// sheet opens (a second one stacking on top would be the un-fixed bug).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<ReservationController> seeded() async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_busy',
      ),
    );
    await c.create(
      ReservationDraft(
        scheduledPickupAt: DateTime(2026, 9, 23, 6, 55),
        pickup: const ReservationPlace(label: 'Klockarvägen 37'),
        destination: const ReservationPlace(label: 'Arlanda Express'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 522,
        paymentMethod: 'Cash',
      ),
    );
    return c;
  }

  Future<void> pumpPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a double-tap on Cancel reservation only opens one confirmation sheet',
    (tester) async {
      final c = await seeded();
      await pumpPhone(
        tester,
        UpcomingReservationPage(reservationId: 'rsv_busy', controller: c),
      );

      final cancelButton = find.text('Cancel reservation');
      await tester.scrollUntilVisible(cancelButton, 300);
      await tester.tap(cancelButton, warnIfMissed: false);
      await tester.tap(cancelButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Cancel reservation?'), findsOneWidget);
    },
  );
}
