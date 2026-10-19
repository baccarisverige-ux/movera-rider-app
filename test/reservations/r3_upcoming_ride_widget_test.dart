import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';

/// Round 3 on the Upcoming ride screen: the driver shows as soon as one
/// accepts (Q12), a driver change is visible, and the cancel sheet shows the
/// free-until time or the admin fee before the rider confirms (Q11).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final pickupAt = DateTime(2026, 10, 16, 8, 0);

  const elin = ReservationDriver(
    firstName: 'Elin',
    id: 'drv_mock_001',
    rating: 4.9,
    vehicle: 'Volvo XC40 Recharge',
    vehicleColor: 'Black',
    plate: 'MVR 204',
    photoAsset: 'assets/images/driver_img.webp',
  );
  const johan = ReservationDriver(
    firstName: 'Johan',
    id: 'drv_mock_002',
    rating: 4.8,
    vehicle: 'Volvo V60',
    vehicleColor: 'Grey',
    plate: 'MVR 771',
    photoAsset: 'assets/images/driver_img.webp',
  );

  Future<ReservationController> seeded({
    required DateTime now,
    ScheduledRideRules rules = ScheduledRideRules.defaults,
  }) async {
    final c = ReservationController(
      store: LocalReservationRepository(
        storage: MemoryReservationStorage(),
        nextId: () => 'rsv_r3',
      ),
      clock: () => now,
      rules: rules,
    );
    await c.create(
      ReservationDraft(
        scheduledPickupAt: pickupAt,
        pickup: const ReservationPlace(label: 'Stockholm Central'),
        destination: const ReservationPlace(label: 'Arlanda Airport'),
        categoryId: 'economy',
        categoryName: 'Movera',
        categoryImage: 'assets/images/rides/movera.webp',
        price: 459,
        paymentMethod: 'Visa •••• 4242',
      ),
    );
    return c;
  }

  Future<void> pumpPage(WidgetTester tester, ReservationController c) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: UpcomingReservationPage(reservationId: 'rsv_r3', controller: c),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCancelSheet(WidgetTester tester) async {
    final cancel = find.text('Cancel reservation');
    await tester.scrollUntilVisible(cancel, 300);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('Cancel reservation?'), findsOneWidget);
  }

  Future<void> confirmAndSkipReason(WidgetTester tester) async {
    // The confirmation sheet's button, on top of the page's own.
    await tester.tap(find.text('Cancel reservation').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
  }

  group('Q12 driver details', () {
    testWidgets('no card while nobody has accepted', (tester) async {
      final c = await seeded(now: DateTime(2026, 10, 15, 9));
      await pumpPage(tester, c);
      expect(find.byKey(const Key('reservation-driver-card')), findsNothing);
      expect(find.text('Driver assigned'), findsNothing);
    });

    testWidgets('name, photo and car appear the moment a driver accepts', (
      tester,
    ) async {
      final c = await seeded(now: DateTime(2026, 10, 15, 9));
      await pumpPage(tester, c);

      await c.applyDriverAssignment('rsv_r3', driver: elin);
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('reservation-driver-card'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Elin')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('Black Volvo XC40 Recharge'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('MVR 204')),
        findsOneWidget,
      );
      final avatar = tester.widget<CircleAvatar>(
        find.descendant(of: card, matching: find.byType(CircleAvatar)),
      );
      expect(
        (avatar.backgroundImage! as AssetImage).assetName,
        'assets/images/driver_img.webp',
      );
      expect(c.byId('rsv_r3')!.status, ReservationStatus.driverAssigned);
    });

    testWidgets('a driver change shows the new driver and says so', (
      tester,
    ) async {
      final c = await seeded(now: DateTime(2026, 10, 15, 9));
      await c.applyDriverAssignment('rsv_r3', driver: elin);
      await pumpPage(tester, c);
      expect(find.byKey(const Key('reservation-driver-changed')), findsNothing);

      await c.applyDriverAssignment('rsv_r3', driver: johan);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reservation-driver-changed')),
        findsOneWidget,
      );
      expect(find.text('Your driver changed'), findsOneWidget);
      expect(
        find.text('Elin can no longer drive you. Johan accepted your ride.'),
        findsOneWidget,
      );
      final card = find.byKey(const Key('reservation-driver-card'));
      expect(
        find.descendant(of: card, matching: find.text('Johan')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Grey Volvo V60')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Elin')),
        findsNothing,
      );
    });

    testWidgets('while a new driver is found, the rider is told why', (
      tester,
    ) async {
      final c = await seeded(now: DateTime(2026, 10, 15, 9));
      await c.applyDriverAssignment('rsv_r3', driver: elin);
      await c.applyDriverCancellation('rsv_r3');
      await pumpPage(tester, c);

      expect(find.byKey(const Key('reservation-driver-left')), findsOneWidget);
      expect(
        find.text(
          "Elin can no longer drive you. We're finding you a new driver.",
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reservation-driver-card')), findsNothing);
    });
  });

  group('Q11 cancel terms', () {
    testWidgets('before the window closes the sheet says it is free', (
      tester,
    ) async {
      final c = await seeded(now: DateTime(2026, 10, 15, 9));
      await pumpPage(tester, c);

      await tester.scrollUntilVisible(
        find.textContaining('Free until Fri, 16 Oct, 07:00'),
        300,
      );
      expect(
        find.text(
          'Free until Fri, 16 Oct, 07:00 (1 h before pickup). '
          'After that, cancelling costs 50 kr.',
        ),
        findsOneWidget,
      );

      await openCancelSheet(tester);
      expect(find.byKey(const Key('reservation-cancel-free')), findsOneWidget);
      expect(find.byKey(const Key('reservation-cancel-fee')), findsNothing);
      expect(
        find.text('Free to cancel until Fri, 16 Oct, 07:00'),
        findsOneWidget,
      );

      await confirmAndSkipReason(tester);
      final ride = c.byId('rsv_r3')!;
      expect(ride.status, ReservationStatus.cancelled);
      expect(ride.cancellationFee, isNull);
      expect(
        find.byKey(const Key('reservation-cancellation-fee')),
        findsNothing,
      );
    });

    testWidgets('inside the window the sheet shows the fee before confirm', (
      tester,
    ) async {
      final c = await seeded(now: DateTime(2026, 10, 16, 7, 20));
      await c.applyDriverAssignment('rsv_r3', driver: elin);
      await pumpPage(tester, c);

      await openCancelSheet(tester);
      expect(find.byKey(const Key('reservation-cancel-fee')), findsOneWidget);
      expect(find.text('Cancellation fee: 50 kr'), findsOneWidget);
      expect(
        find.text(
          'Free cancellation ended at 07:00, 1 h before pickup. '
          'You pay 50 kr if you cancel now.',
        ),
        findsOneWidget,
      );

      // Keep reservation charges nothing and cancels nothing.
      await tester.tap(find.text('Keep reservation'));
      await tester.pumpAndSettle();
      expect(c.byId('rsv_r3')!.status, ReservationStatus.driverAssigned);

      await openCancelSheet(tester);
      await confirmAndSkipReason(tester);
      final ride = c.byId('rsv_r3')!;
      expect(ride.status, ReservationStatus.cancelled);
      expect(ride.cancellationFee, const Money(5000));
      expect(
        find.byKey(const Key('reservation-cancellation-fee')),
        findsOneWidget,
      );
      expect(find.text('Cancellation fee'), findsOneWidget);
    });

    testWidgets('the admin fee and window come from the config', (
      tester,
    ) async {
      final c = await seeded(
        now: DateTime(2026, 10, 16, 6, 30),
        rules: const ScheduledRideRules(
          freeCancelMinutesBeforePickup: 120,
          lateCancelFee: Money(7500),
        ),
      );
      await pumpPage(tester, c);

      await openCancelSheet(tester);
      expect(find.text('Cancellation fee: 75 kr'), findsOneWidget);
      expect(
        find.text(
          'Free cancellation ended at 06:00, 2 h before pickup. '
          'You pay 75 kr if you cancel now.',
        ),
        findsOneWidget,
      );
      await confirmAndSkipReason(tester);
      expect(c.byId('rsv_r3')!.cancellationFee, const Money(7500));
    });

    testWidgets('the terms page states the admin cancel rule', (tester) async {
      final c = await seeded(now: DateTime(2026, 10, 15, 9));
      await pumpPage(tester, c);
      final link = find.text('View scheduled ride terms');
      await tester.scrollUntilVisible(link, 300);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(find.text('Scheduled ride terms'), findsOneWidget);
      expect(
        find.text(
          'Cancelling is free until 1 h before pickup. After that, it costs '
          '50 kr. Other fees and time windows apply only when they are shown '
          'before booking.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('currently published'), findsNothing);
    });
  });
}
