import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI-19: Ride History built every card up front; it now builds the ones on
/// screen and scrolls to the rest.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Reservation ride(int i) {
    final endedAt = DateTime(2026, 9, 1).add(Duration(hours: i));
    return Reservation(
      reservationId: 'ondemand-$i',
      createdAt: endedAt.subtract(const Duration(minutes: 20)),
      scheduledPickupAt: endedAt,
      pickup: const ReservationPlace(label: 'Pickup'),
      destination: ReservationPlace(label: 'Stop $i'),
      categoryId: 'economy',
      categoryName: 'Movera',
      categoryImage: 'assets/images/rides/movera.webp',
      price: 259,
      paymentMethod: 'Apple Pay',
      status: ReservationStatus.completed,
    );
  }

  testWidgets('100 completed rides: only the visible cards are built', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rides = [for (var i = 0; i < 100; i++) ride(i)];
    await tester.pumpWidget(
      MaterialApp(
        home: RideHistory(
          reservations: ReservationController(
            store: LocalReservationRepository(
              storage: MemoryReservationStorage(),
            ),
          ),
          onDemandReader: () async => rides,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();

    // The list hands out cards on demand instead of holding all 100.
    final list = tester.widget<ListView>(find.byType(ListView).last);
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    final built = find.byType(ReservationHistoryCard).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(30));

    await tester.dragUntilVisible(
      find.textContaining('Stop 0'),
      find.byType(Scrollable).last,
      const Offset(0, -600),
    );
    expect(find.textContaining('Stop 0'), findsOneWidget);
  });
}
