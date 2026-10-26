import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.idle);
  });

  Widget waitingCardHost(MatchedDriver driver) {
    return MaterialApp(
      home: Scaffold(
        body: WaitingDriverCard(
          driver: driver,
          rideId: 'phase53-driver-card',
          onOpenProfile: () {},
          onCall: () {},
          onMore: () {},
        ),
      ),
    );
  }

  testWidgets(
    'Waiting driver card does not crash when matching supplies an empty firstName',
    (tester) async {
      await tester.pumpWidget(
        waitingCardHost(const MatchedDriver(id: 'driver-empty', firstName: '')),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(WaitingDriverCard), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
    },
  );

  testWidgets('Waiting driver card still renders a normal driver name', (
    tester,
  ) async {
    await tester.pumpWidget(
      waitingCardHost(
        const MatchedDriver(id: 'driver-amina', firstName: 'Amina'),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Amina'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });

  test('driver domain models safely represent direct empty names', () {
    const matched = MatchedDriver(id: 'direct-empty', firstName: '');
    const scheduled = ReservationDriver(firstName: '');

    expect(matched.displayFirstName, 'Driver');
    expect(matched.initial, isEmpty);
    expect(scheduled.displayFirstName, 'Driver');
    expect(scheduled.initial, isEmpty);
  });

  testWidgets(
    'upcoming reservation driver card does not crash with an empty direct name',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReservationDriverCard(
              driver: ReservationDriver(firstName: ''),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ReservationDriverCard), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'unmounting Waiting during driver-cancel recovery has no context exception',
    (tester) async {
      const rideId = 'phase53-unmount-driver-cancel';
      await RideSnapshotStore.save(
        RideSnapshot(
          status: RideStatus.driverAssigned,
          savedAt: DateTime(2026, 9, 24, 7),
          pickupAddress: 'Stockholm pickup',
          destinationAddress: 'Stockholm destination',
          pickupLat: 59.3293,
          pickupLng: 18.0686,
          destinationLat: 59.3326,
          destinationLng: 18.0649,
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          rideId: rideId,
        ),
      );
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.driverAssigned,
        id: rideId,
      );

      final realtime = MockRideRealtime(assignAfter: const Duration(hours: 1));
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('phase53-root')),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => WaitingForDriver(
            pickupAddress: 'Stockholm pickup',
            destinationAddress: 'Stockholm destination',
            pickupPosition: const LatLng(59.3293, 18.0686),
            destinationPosition: const LatLng(59.3326, 18.0649),
            rideType: 'Movera',
            price: 259,
            paymentMethod: 'Apple Pay',
            rideId: rideId,
            realtime: realtime,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      realtime.holdAssignment();
      realtime.emit(RideStatus.cancelledByDriver);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The search restarts on its own; there is nothing to tap.
      expect(find.text('Keep searching'), findsNothing);

      // Unmount the entire route tree while the async recovery chain is still
      // unwinding. Any post-await context use must be protected by mounted.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('phase53-unmounted'))),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('phase53-unmounted'), findsOneWidget);
      realtime.holdAssignment();
    },
  );
}
