import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';

/// Batch 9 Phase 106 — U4 client mitigation: a due scheduled ride that never
/// gets a driver must surface an honest "No driver found — rebook or cancel"
/// state instead of an orange "Now" chrono forever.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final pickupAt = DateTime(2026, 9, 23, 6, 55);

  Future<ReservationController> seeded() async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_106',
      ),
    );
    await c.create(
      ReservationDraft(
        scheduledPickupAt: pickupAt,
        estimatedDropoffAt: pickupAt.add(const Duration(minutes: 30)),
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
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: home)));
  }

  test('a due ride with no driver times out into "no driver found"', () async {
    final c = await seeded();
    await c.startLiveIfDue(now: pickupAt);
    final ride = c.byId('rsv_106')!;
    expect(ride.status, ReservationStatus.driverAssignmentPending);
    expect(c.isNoDriverFound(ride, now: pickupAt), isFalse);
    expect(
      c.isNoDriverFound(ride, now: pickupAt.add(const Duration(minutes: 4))),
      isFalse,
    );
    final late = pickupAt.add(ReservationController.noDriverFoundAfter);
    expect(c.isNoDriverFound(ride, now: late), isTrue);
    expect(c.noDriverFound(now: late).map((r) => r.reservationId), ['rsv_106']);
  });

  test('an assigned driver never reads as "no driver found"', () async {
    final c = await seeded();
    await c.applyDriverAssignment(
      'rsv_106',
      driver: const ReservationDriver(firstName: 'Amina'),
    );
    final late = pickupAt.add(const Duration(hours: 1));
    expect(c.isNoDriverFound(c.byId('rsv_106')!, now: late), isFalse);
  });

  testWidgets('chrono shows the stuck state and cancel resolves it', (
    tester,
  ) async {
    final c = await seeded();
    final late = pickupAt.add(const Duration(minutes: 6));
    await pumpPhone(
      tester,
      HomeReservationChrono(controller: c, now: () => late),
    );
    await tester.pumpAndSettle();
    // The state is surfaced proactively, not only on tap.
    expect(
      find.byKey(const Key('reservation-no-driver-found')),
      findsOneWidget,
    );
    expect(find.text('No driver found'), findsOneWidget);
    // Without a rebook entry point only cancel is offered.
    expect(find.byKey(const Key('reservation-no-driver-rebook')), findsNothing);
    expect(find.text('Now'), findsNothing);

    await tester.tap(find.byKey(const Key('reservation-no-driver-cancel')));
    await tester.pumpAndSettle();
    final ride = c.byId('rsv_106')!;
    expect(ride.status.isCancelled, isTrue);
    expect(ride.cancellationReason, ReservationController.noDriverFoundReason);
    expect(find.byType(HomeReservationChrono), findsOneWidget);
    expect(find.byKey(const Key('reservation-chrono-no-driver')), findsNothing);
  });

  testWidgets('rebook cancels the stuck reservation and opens scheduling', (
    tester,
  ) async {
    final c = await seeded();
    final late = pickupAt.add(const Duration(minutes: 6));
    var rebooked = 0;
    await pumpPhone(
      tester,
      HomeReservationChrono(
        controller: c,
        now: () => late,
        onRebook: () => rebooked++,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reservation-no-driver-rebook')));
    await tester.pumpAndSettle();
    expect(rebooked, 1);
    expect(c.byId('rsv_106')!.status.isCancelled, isTrue);
  });

  testWidgets('dismissing keeps the reservation and tapping reopens it', (
    tester,
  ) async {
    final c = await seeded();
    final late = pickupAt.add(const Duration(minutes: 6));
    await pumpPhone(
      tester,
      HomeReservationChrono(controller: c, now: () => late),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reservation-no-driver-found')), findsNothing);
    expect(c.byId('rsv_106')!.status.isUpcoming, isTrue);
    expect(
      find.byKey(const Key('reservation-chrono-no-driver')),
      findsOneWidget,
    );
    expect(find.text('Now'), findsNothing);

    await tester.tap(find.byType(HomeReservationChrono));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('reservation-no-driver-found')),
      findsOneWidget,
    );
  });
}
