import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/reservations/presentation/review_changes.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/reservations/presentation/scheduled_ride_terms.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const realDriver = ReservationDriver(
    firstName: 'Amina',
    rating: 4.9,
    vehicle: 'Volvo EX40',
    plate: 'ABC 123',
  );

  Future<ReservationController> seeded() async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_ui',
      ),
    );
    await c.create(
      ReservationDraft(
        scheduledPickupAt: DateTime(2026, 9, 23, 6, 55),
        estimatedDropoffAt: DateTime(2026, 9, 23, 7, 26),
        pickup: const ReservationPlace(
          label: 'Klockarvägen 37',
          subtitle: 'Södertälje',
        ),
        destination: const ReservationPlace(
          label: 'Arlanda Express',
          subtitle: 'Stockholm',
        ),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 522,
        paymentMethod: 'Cash',
        note: 'Bags · Pet',
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
  }

  testWidgets('confirmation shows Movera reservation card not a toast', (
    tester,
  ) async {
    final c = await seeded();
    await pumpPhone(
      tester,
      RideScheduledPage(reservationId: 'rsv_ui', controller: c),
    );
    expect(find.text('Your ride is scheduled'), findsOneWidget);
    expect(find.textContaining('notify you'), findsOneWidget);
    expect(find.text('Driver pending'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Edit reservation'), findsOneWidget);
    expect(find.text('Movera'), findsWidgets);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Payment'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Plan a return ride'), 400);
    expect(find.text('Plan a return ride'), findsOneWidget);
    expect(find.text('Bags · Pet'), findsOneWidget);
    expect(find.text('Your reservation is confirmed'), findsNothing);
    expect(find.textContaining('Uber'), findsNothing);
  });

  testWidgets(
    'scheduled Back reverses one route while Done returns to the root',
    (tester) async {
      final c = await seeded();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (rootContext) => Scaffold(
              body: Column(
                children: [
                  const Text('root-home'),
                  TextButton(
                    key: const ValueKey('open-middle'),
                    onPressed: () {
                      Navigator.push(
                        rootContext,
                        MaterialPageRoute<void>(
                          builder: (_) => Builder(
                            builder: (middleContext) => Scaffold(
                              body: Column(
                                children: [
                                  const Text('middle-screen'),
                                  TextButton(
                                    key: const ValueKey('open-scheduled'),
                                    onPressed: () {
                                      RideScheduledPage.open(
                                        middleContext,
                                        reservationId: 'rsv_ui',
                                        controller: c,
                                      );
                                    },
                                    child: const Text('Open scheduled'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open middle'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-middle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-scheduled')));
      await tester.pumpAndSettle();
      expect(find.text('Your ride is scheduled'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('middle-screen'), findsOneWidget);
      expect(find.text('root-home'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('open-scheduled')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('root-home'), findsOneWidget);
      expect(find.text('middle-screen'), findsNothing);
    },
  );

  testWidgets('history lists the reservation immediately under Upcoming', (
    tester,
  ) async {
    final c = await seeded();
    await pumpPhone(tester, RideHistory(reservations: c));
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Klockarvägen 37 → Arlanda Express'), findsOneWidget);
    expect(find.text('Driver pending'), findsOneWidget);
    expect(find.text('No upcoming rides'), findsNothing);
  });

  testWidgets('details match the reservation and keep the same id on edit', (
    tester,
  ) async {
    final c = await seeded();
    await pumpPhone(
      tester,
      UpcomingReservationPage(reservationId: 'rsv_ui', controller: c),
    );
    expect(find.text('Upcoming ride'), findsOneWidget);
    expect(find.text('Klockarvägen 37'), findsWidgets);
    expect(find.text('Arlanda Express'), findsWidgets);
    expect(find.text('Reservation confirmed'), findsOneWidget);
    expect(find.textContaining('when a driver is assigned'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bags · Pet'), 300);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Bags · Pet'), findsWidgets);
    expect(c.byId('rsv_ui')!.paymentMethod, 'Cash');
    await c.update(
      'rsv_ui',
      ReservationPatch(scheduledPickupAt: DateTime(2026, 9, 24, 8, 15)),
    );
    await tester.pump();
    expect(c.byId('rsv_ui')!.reservationId, 'rsv_ui');
    expect(c.byId('rsv_ui')!.scheduledPickupAt, DateTime(2026, 9, 24, 8, 15));
    expect(c.byId('rsv_ui')!.paymentMethod, 'Cash');
    expect(c.byId('rsv_ui')!.destination.label, 'Arlanda Express');
  });

  test('remaining time is compact like 1d 2h', () {
    expect(
      ReservationFormat.remainingCompact(
        DateTime(2026, 9, 15, 10),
        now: DateTime(2026, 9, 13, 8),
      ),
      '2d 2h',
    );
    expect(
      ReservationFormat.remainingParts(
        DateTime(2026, 9, 15, 10),
        now: DateTime(2026, 9, 13, 8),
      ),
      (primary: '2d', secondary: '2h'),
    );
  });

  testWidgets('chrono appears after a reservation and opens its details', (
    tester,
  ) async {
    final c = await seeded();
    final now = DateTime(2026, 9, 13, 21);
    await pumpPhone(
      tester,
      Scaffold(
        body: HomeReservationChrono(controller: c, now: () => now),
      ),
    );
    expect(find.text('Chrono'), findsNothing);
    expect(find.text('9d'), findsOneWidget);
    expect(find.text('9h'), findsOneWidget);
    await tester.tap(find.byType(HomeReservationChrono));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming ride'), findsOneWidget);
    expect(find.text('Klockarvägen 37'), findsWidgets);
  });

  testWidgets('driver details show as soon as a driver accepts', (
    tester,
  ) async {
    // Round 3 Q12: the rider sees the driver right away, not near pickup.
    final c = await seeded();
    await c.assignMockDriver('rsv_ui', driver: realDriver);
    await pumpPhone(
      tester,
      UpcomingReservationPage(reservationId: 'rsv_ui', controller: c),
    );
    expect(find.byKey(const Key('reservation-driver-card')), findsOneWidget);
    expect(find.text('Amina'), findsOneWidget);
    expect(find.text('Volvo EX40'), findsOneWidget);
    expect(find.text('ABC 123'), findsOneWidget);
    expect(
      find.text('Driver details appear when your driver is on the way.'),
      findsNothing,
    );
  });

  testWidgets('with the admin switch off, details wait for the way there', (
    tester,
  ) async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_ui',
      ),
      rules: const ScheduledRideRules(showDriverOnAccept: false),
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
    await c.assignMockDriver('rsv_ui', driver: realDriver);
    await pumpPhone(
      tester,
      UpcomingReservationPage(reservationId: 'rsv_ui', controller: c),
    );
    expect(find.text('Amina'), findsNothing);
    expect(
      find.text('Driver details appear when your driver is on the way.'),
      findsOneWidget,
    );
  });

  test('pickup time without a real driver stays assignment pending', () async {
    final c = await seeded();
    await c.startLiveIfDue(now: DateTime(2026, 9, 23, 6, 55));
    final ride = c.byId('rsv_ui')!;
    expect(ride.status, ReservationStatus.driverAssignmentPending);
    expect(ride.driver, isNull);
    expect(ride.driverAssigned, isFalse);
    expect(ride.revealsDriver, isFalse);
  });

  test('pickup time with a real driver starts the live on-the-way state', () async {
    final c = await seeded();
    await c.assignMockDriver('rsv_ui', driver: realDriver);
    await c.startLiveIfDue(now: DateTime(2026, 9, 23, 6, 55));
    final ride = c.byId('rsv_ui')!;
    expect(ride.status, ReservationStatus.driverEnRoute);
    expect(ride.revealsDriver, isTrue);
    expect(ride.driver?.firstName, 'Amina');
    final page = ReservationLiveRide.pageFor(ride);
    expect(page.pickupAddress, 'Klockarvägen 37');
    expect(page.destinationAddress, 'Arlanda Express');
    expect(page.rideType, 'Movera');
    expect(page.driver?.firstName, 'Amina');
    expect(page.driver?.plate, 'ABC 123');
  });

  testWidgets('assigned driver updates the same history card', (tester) async {
    final c = await seeded();
    await pumpPhone(tester, RideHistory(reservations: c));
    expect(find.text('Driver pending'), findsOneWidget);
    await c.assignMockDriver('rsv_ui', driver: realDriver);
    await tester.pump();
    expect(find.text('Driver assigned'), findsOneWidget);
    expect(find.text('Driver pending'), findsNothing);
    expect(c.all, hasLength(1));
  });

  testWidgets('cancel moves the same reservation to Cancelled', (tester) async {
    final c = await seeded();
    await c.cancel('rsv_ui', reason: 'plans_changed');
    await pumpPhone(tester, RideHistory(reservations: c));
    await tester.tap(find.text('Cancelled'));
    await tester.pumpAndSettle();
    expect(find.text('Klockarvägen 37 → Arlanda Express'), findsOneWidget);
    expect(c.cancelled().single.reservationId, 'rsv_ui');
  });

  testWidgets('policy page is Movera terms', (tester) async {
    final c = await seeded();
    await pumpPhone(tester, ScheduledRideTermsPage(controller: c));
    expect(find.text('Scheduled ride terms'), findsOneWidget);
    expect(find.textContaining('Uber'), findsNothing);
    expect(find.textContaining('SEK 160'), findsNothing);
  });

  testWidgets('review changes compares price and keeps the current ride', (
    tester,
  ) async {
    final c = await seeded();
    final original = c.byId('rsv_ui')!;
    final draft = ReservationDraft(
      scheduledPickupAt: DateTime(2026, 9, 24, 8, 15),
      pickup: const ReservationPlace(label: 'T-Centralen'),
      destination: const ReservationPlace(label: 'Bromma'),
      categoryId: 'comfort',
      categoryName: 'Comfort',
      categoryImage: 'assets/images/rides/comfort.webp',
      price: 562,
      paymentMethod: 'Cash',
    );
    await pumpPhone(
      tester,
      ReviewChangesPage(original: original, draft: draft, controller: c),
    );
    expect(find.text('Review your changes'), findsOneWidget);
    expect(find.text('Confirm changes'), findsOneWidget);
    expect(find.text('Keep current reservation'), findsOneWidget);
    expect(find.textContaining('40 kr more'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No additional change charge'),
      300,
    );
    expect(find.text('No additional change charge'), findsOneWidget);
    expect(find.textContaining('Uber'), findsNothing);
    await tester.tap(find.text('Keep current reservation'));
    await tester.pump();
    expect(c.byId('rsv_ui')!.price, 522);
    expect(c.byId('rsv_ui')!.reservationId, 'rsv_ui');
  });
}
