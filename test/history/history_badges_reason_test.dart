import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R-UI UI-06 / UI-07: History showed reservation-dispatch badges on
/// finished rides ("Driver pending" on a cancelled ride, "Driver assigned"
/// on a completed one), the raw reason code "plans_changed", and no way to
/// get help from a past ride.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Reservation ride(
    String id,
    ReservationStatus status, {
    String? reason,
    Money? fee,
    bool driver = true,
  }) {
    final endedAt = DateTime.now().subtract(const Duration(hours: 2));
    return Reservation(
      reservationId: 'ondemand-$id',
      createdAt: endedAt.subtract(const Duration(minutes: 20)),
      scheduledPickupAt: endedAt,
      pickup: const ReservationPlace(label: 'Sveavägen 1'),
      destination: const ReservationPlace(label: 'Arlanda Airport'),
      categoryId: 'economy',
      categoryName: 'Movera',
      categoryImage: 'assets/images/rides/movera.webp',
      price: 659,
      paymentMethod: 'Apple Pay',
      status: status,
      cancellationReason: reason,
      cancellationFee: fee,
      driver: driver ? const ReservationDriver(firstName: 'Amina') : null,
    );
  }

  test('finished rides get a status, not a driver badge', () {
    expect(
      ReservationFormat.historyStatus(ride('a', ReservationStatus.completed)),
      'Completed',
    );
    expect(
      ReservationFormat.historyStatus(ride('b', ReservationStatus.cancelled)),
      'Cancelled',
    );
    expect(
      ReservationFormat.historyStatus(
        ride('c', ReservationStatus.cancelled, fee: const Money(5000)),
      ),
      'Cancelled · fee 50 kr',
    );
    expect(
      ReservationFormat.historyStatus(ride('d', ReservationStatus.scheduled)),
      isNull,
    );
  });

  test('reason codes read as labels', () {
    expect(ReservationFormat.reasonLabel('plans_changed'), 'Plans changed');
    expect(
      ReservationFormat.reasonLabel('wait_too_long'),
      'The wait is taking too long',
    );
    expect(ReservationFormat.reasonLabel('system_no_driver'), 'No driver found');
    expect(ReservationFormat.reasonLabel('admin_safety'), 'Cancelled by Movera');
    expect(ReservationFormat.reasonLabel('No driver found'), 'No driver found');
    expect(ReservationFormat.reasonLabel('some_new_code'), 'Some new code');
  });

  Future<void> pumpHistory(WidgetTester tester, List<Reservation> rides) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
  }

  testWidgets('cancelled ride: status chip, reason label, get help', (
    tester,
  ) async {
    await pumpHistory(tester, [
      ride('x1', ReservationStatus.cancelled, reason: 'plans_changed'),
    ]);
    await tester.tap(find.text('Cancelled').first);
    await tester.pumpAndSettle();

    expect(find.text('Driver pending'), findsNothing);
    expect(find.text('Driver assigned'), findsNothing);
    expect(find.byKey(const ValueKey('history-status-chip')), findsOneWidget);
    expect(find.text('659 kr'), findsOneWidget);

    await tester.tap(find.textContaining('Arlanda Airport').first);
    await tester.pumpAndSettle();
    expect(find.text('Reason: Plans changed'), findsOneWidget);
    expect(find.textContaining('plans_changed'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('history-get-help')));
    await tester.pumpAndSettle();
    expect(find.byType(SelectIssue), findsOneWidget);
  });

  testWidgets('completed ride says Completed, not Driver assigned', (
    tester,
  ) async {
    await pumpHistory(tester, [ride('x2', ReservationStatus.completed)]);
    await tester.tap(find.text('Completed').first);
    await tester.pumpAndSettle();
    expect(find.text('Driver assigned'), findsNothing);
    final chip = find.byKey(const ValueKey('history-status-chip'));
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Completed')),
      findsOneWidget,
    );
  });
}
