import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u52: `closed` (completed, paid and rated) is terminal but not a
/// completed surface, so an in-trip Waiting that resynced straight to it
/// sent it to markExternalTerminal, which throws ArgumentError for closed.
/// The throw happened after tracking was disposed, so Waiting stayed
/// frozen with its snapshot never cleared.
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
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  RideSnapshot inTripSnapshot(String rideId) => RideSnapshot(
    status: RideStatus.tripInProgress,
    savedAt: DateTime.now(),
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
  );

  testWidgets(
    'a closed projection ends an in-trip Waiting as a finished trip',
    (tester) async {
      const rideId = 'waiting-closed-resync';
      await RideSnapshotStore.save(inTripSnapshot(rideId));
      AppScope.instance.ride.restoreFromBackend(
        RideStatus.tripInProgress,
        id: rideId,
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('audit-root'))),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const WaitingForDriver(
            pickupAddress: 'Stockholm pickup',
            destinationAddress: 'Stockholm destination',
            pickupPosition: LatLng(59.3293, 18.0686),
            destinationPosition: LatLng(59.3326, 18.0649),
            rideType: 'Movera',
            price: 259,
            paymentMethod: 'Apple Pay',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(WaitingForDriver), findsOneWidget);

      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      realtime.emit(RideStatus.closed);
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // No error sheet: the trip finished normally; the rider is back Home.
      expect(tester.takeException(), isNull);
      expect(find.byType(RideTerminalStateSheet), findsNothing);
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.text('audit-root'), findsOneWidget);
      expect(AppScope.instance.ride.status, RideStatus.closed);
      expect(await RideSnapshotStore.read(), isNull);

      // The trip the rider took is in History as completed.
      final history = await OnDemandRideHistoryStore.read();
      expect(history, hasLength(1));
      expect(history.single.reservationId, 'ondemand-$rideId');
      expect(history.single.status, ReservationStatus.completed);
    },
  );
}
