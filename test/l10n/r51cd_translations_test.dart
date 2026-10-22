import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/home_reservation_chrono.dart';
import 'package:movera_rider/features/ride_booking/data/driver_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/trip_detail.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/responsive_harness.dart';

/// Wave 5 R5.1 (parts c and d): labels that showed English, broken
/// sentences or an English decimal mark in French and Swedish.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    L10n.use('en');
    LastCompletedRide.clear();
  });

  RideSnapshot completed({MatchedDriver? driver, String payment = 'Cash'}) =>
      RideSnapshot(
        status: RideStatus.tripCompleted,
        rideId: 'r51cd_done',
        pickupAddress: 'Sveavägen 1',
        destinationAddress: 'Hornsgatan 2',
        pickupLat: 59.34,
        pickupLng: 18.05,
        destinationLat: 59.31,
        destinationLng: 18.04,
        rideType: 'Movera',
        price: 259,
        paymentMethod: payment,
        savedAt: DateTime(2026, 9, 18, 7, 5),
        driver: driver,
      );

  Future<void> pumpIn(
    WidgetTester tester,
    String code,
    Widget screen, {
    Size viewport = const Size(390, 844),
  }) async {
    L10n.use(code);
    await pumpMoveraScreen(
      tester,
      screen,
      viewport: viewport,
      locale: Locale(code),
    );
    await tester.pump();
  }

  for (final code in ['fr', 'sv']) {
    group(code, () {
      testWidgets('rider-j8-7: a due reservation reads "now", not "in Now"', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final pickupAt = DateTime(2026, 10, 2, 9, 30);
        final reservations = ReservationController(
          store: LocalReservationRepository(
            storage: MemoryReservationStorage(),
            nextId: () => 'rsv_j87',
          ),
        );
        await reservations.create(
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
        await reservations.applyDriverAssignment(
          'rsv_j87',
          driver: const ReservationDriver(firstName: 'Amina'),
        );
        // The French face text overflowing the disc is rider-u160, fixed
        // in its own batch; only the label is under test here.
        final errors = await collectFlutterErrors(
          () => pumpIn(
            tester,
            code,
            Scaffold(
              body: Center(
                child: HomeReservationChrono(
                  controller: reservations,
                  now: () => pickupAt.subtract(const Duration(seconds: 30)),
                ),
              ),
            ),
          ),
        );
        expect(errors.where((e) => !e.contains('overflowed')), isEmpty);
        // The label leads the merged node; the face's own text follows.
        expect(
          find.bySemanticsLabel(
            RegExp('^${RegExp.escape(L10n.current.reservationNow)}\n'),
          ),
          findsOneWidget,
        );
        semantics.dispose();
      });

      test('rider-70: completed driver fallbacks are translated', () {
        L10n.use(code);
        LastCompletedRide.remember(
          completed(
            driver: const MatchedDriver(id: 'drv_70', firstName: 'Elin'),
          ),
        );
        final bare = const DriverRepository().current()!;
        expect(bare.vehicle, L10n.current.driverVehicleUnavailable);
        expect(bare.tagline, L10n.current.driverTaglineDefault);

        LastCompletedRide.remember(
          completed(
            driver: const MatchedDriver(
              id: 'drv_70',
              firstName: 'Elin',
              tripCount: 12,
            ),
          ),
        );
        expect(
          const DriverRepository().current()!.tagline,
          L10n.current.driverTripsCompleted(12),
        );
        expect(L10n.current.driverTripsCompleted(12), contains('12'));
      });

      testWidgets('rider-u182: receipt names Wallet and Card in the language', (
        tester,
      ) async {
        for (final (stored, shown) in [
          ('Movera Wallet', () => L10n.current.moveraWallet),
          ('Card', () => L10n.current.payCard),
        ]) {
          await pumpIn(
            tester,
            code,
            Scaffold(
              body: RideCompletedTripDetail(
                controller: RideCompleteController(
                  trips: TripReceiptRepository(
                    receipt: TripReceipt(
                      pickup: 'Sveavägen 1',
                      destination: 'Hornsgatan 2',
                      total: '259 kr',
                      method: stored,
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text(shown()), findsOneWidget);
          expect(find.text(stored), findsNothing);
        }
      });
    });
  }
}
