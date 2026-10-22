import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/application/scheduled_ride_booking.dart';
import 'package:movera_rider/features/ride_selection/domain/booking_mode.dart';

import '../reservations/scheduled_quote_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'schedule -> countdown -> assigned live ride -> completion -> Home',
    (tester) async {
      // rider-63: the pick is Stockholm wall-clock time and now is an
      // instant, so the countdown is right on a device in any zone.
      final now = ZoneClock.toUtc(DateTime(2026, 9, 26, 8), ZoneClock.stockholm);
      final pickupAt = DateTime(2026, 9, 26, 10, 15);
      final reservations = ReservationController(
        store: LocalReservationRepository(
          storage: MemoryReservationStorage(),
          nextId: () => 'journey-reservation-1',
        ),
      );
      final selection = RideSelectionController(
        bookingMode: BookingMode.scheduled,
      );
      addTearDown(selection.dispose);
      selection.scheduleFor(pickupAt);
      final ride = selection.rideById('economy');
      selection.selectRide(ride.id, ride.price);
      // ARCH-16: Select Ride has the server quote before Book for later.
      adoptScheduledQuote(selection, ride.id);

      Reservation? created;
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          ensureScreenSize: true,
          builder: (_, child) => MaterialApp(
            home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      created = await ScheduledRideBooking.confirm(
                        reservations: reservations,
                        selection: selection,
                        pickup: const ReservationPlace(
                          label: 'Stockholm Central',
                          lat: 59.3293,
                          lng: 18.0686,
                        ),
                        destination: const ReservationPlace(
                          label: 'Arlanda Airport',
                          lat: 59.6519,
                          lng: 17.9186,
                        ),
                      );
                      if (!context.mounted) return;
                      await RideScheduledPage.open(
                        context,
                        reservationId: created!.reservationId,
                        controller: reservations,
                      );
                    },
                    child: const Text('Schedule Movera'),
                  ),
                  HomeReservationChrono(
                    controller: reservations,
                    now: () => now,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
      await tester.pumpAndSettle();

      expect(find.text('Schedule Movera'), findsOneWidget);
      await tester.tap(find.text('Schedule Movera'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(created?.reservationId, 'journey-reservation-1');
      expect(find.text('Your ride is scheduled'), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.byType(RideScheduledPage)),
        )?.settings.name,
        AppRoutes.reservationScheduled,
      );

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeReservationChrono), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);
      expect(find.text('15m'), findsOneWidget);
      expect(
        reservations.byId('journey-reservation-1')?.status,
        ReservationStatus.scheduled,
      );

      const driver = ReservationDriver(
        firstName: 'Amina',
        rating: 4.9,
        vehicle: 'Volvo EX40',
        plate: 'ABC 123',
      );
      await reservations.applyDriverAssignment(
        'journey-reservation-1',
        driver: driver,
      );
      await reservations.update(
        'journey-reservation-1',
        const ReservationPatch(status: ReservationStatus.driverEnRoute),
      );
      await tester.pump();

      await tester.tap(find.byType(HomeReservationChrono));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(WaitingForDriver), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.byType(WaitingForDriver)),
        )?.settings.name,
        AppRoutes.reservationLive,
      );
      expect(find.textContaining('Amina'), findsWidgets);

      await reservations.update(
        'journey-reservation-1',
        const ReservationPatch(status: ReservationStatus.inProgress),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Ride in progress'), findsOneWidget);

      await reservations.update(
        'journey-reservation-1',
        const ReservationPatch(status: ReservationStatus.completed),
      );
      // The live reservation event first parks the active map at end-of-frame,
      // then replaces Waiting with the completion route. Pump those stages in
      // order instead of jumping fake time before navigation is scheduled.
      await tester.pump();
      await tester.pump();
      for (
        var i = 0;
        i < 10 && find.byType(RideCompleted).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(RideCompleted), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(RideCompleted)))
            ?.settings
            .name,
        AppRoutes.rideCompleted,
      );
      expect(
        reservations.byId('journey-reservation-1')?.status,
        ReservationStatus.completed,
      );

      final done = find.byKey(
        const ValueKey<String>('ride-completed-done'),
      );
      await tester.ensureVisible(done);
      await tester.tap(done);
      await tester.pumpAndSettle();

      expect(find.byType(RideCompleted), findsNothing);
      // Home keeps the chrono shell mounted permanently. A completed
      // reservation must disappear from its data/content rather than remove
      // the Home widget itself.
      expect(find.byType(HomeReservationChrono), findsOneWidget);
      expect(reservations.upcoming(), isEmpty);
      expect(find.text('2h'), findsNothing);
      expect(find.text('15m'), findsNothing);
      expect(find.text('Schedule Movera'), findsOneWidget);

      // HomeReservationChrono owns a periodic refresh while mounted.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
