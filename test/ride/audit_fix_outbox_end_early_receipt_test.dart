import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u32: a queued (offline) end-early that the outbox flush later
/// delivers sets the trip's fare to the distance price on the server. The
/// restored trip then resyncs to cancelledByRider, and Waiting committed it
/// knowing neither the amount charged nor the rider's reason: no receipt
/// amount, History "Booked price 259 kr" with no reason, though 80 kr was
/// charged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const rideId = 'outbox-end-early-1';
  final posts = <http.Request>[];

  /// The server after the reconnect: the trip is still in trip when the
  /// outbox re-reads it, and end-early closes it at the distance price.
  ApiClient server() => ApiClient(
    client: MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({'tripId': rideId, 'status': 'in_trip', 'version': 3}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      posts.add(request);
      return http.Response(
        jsonEncode({
          'code': 'OK',
          'ride': {
            'tripId': rideId,
            'status': 'cancelled_by_rider',
            'version': 4,
            'fare': {'amountMinor': 8000, 'currency': 'SEK'},
            'cancellation': {
              'actor': 'rider',
              'reasonCode': 'plans_changed',
              'fee': null,
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  RideSnapshot inTrip() => RideSnapshot(
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
    version: 3,
  );

  /// The rider tapped End trip on board with no connection: the command
  /// waits in the outbox, then the reconnect flush sends it.
  Future<void> flushQueuedEndEarly() async {
    await PendingCancelStore.add(
      const PendingCancel(
        rideId: rideId,
        reasonId: 'plans_changed',
        idempotencyKey: 'k-end-early',
        command: PendingCancelCommand.endEarly,
        expectedVersion: 3,
      ),
    );
    final results = await FindingDriverController.flushPendingCancels(
      api: server(),
    );
    expect(results[rideId], PendingCancelResult.sent);
    expect(posts.single.url.path, '/api/v1/rides/$rideId/end-early');
    expect(await PendingCancelStore.all(), isEmpty);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    LastCompletedRide.clear();
    posts.clear();
    FindingDriverController.active = null;
    await FindingDriverController.debugStopReconnectFlush();
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
    await RideSnapshotStore.save(inTrip());
  });

  test('the delivered end-early keeps what was charged and why', () async {
    await flushQueuedEndEarly();
    // Realtime then reports the server's outcome to the restored trip.
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.cancelledByRider,
      id: rideId,
    );

    final controller = ActiveRideController();
    await controller.completeServerConfirmedCancel();

    expect(controller.endedEarly?.charged, const Money(8000));
    expect(LastCompletedRide.charged, const Money(8000));
    final record = (await OnDemandRideHistoryStore.read()).single;
    expect(record.endedEarly, isTrue);
    expect(record.chargedFare, const Money(8000));
    expect(ReservationFormat.price(record), '80 kr');
    expect(record.cancellationReason, 'plans_changed');
    expect(
      ReservationFormat.reasonLabel(record.cancellationReason!),
      'Plans changed',
    );
  });

  testWidgets('the restored trip shows the amount on its ended-early summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await flushQueuedEndEarly();
    AppScope.instance.ride
      ..restoreFromBackend(RideStatus.tripInProgress, id: rideId)
      ..authoritativeVersion = 3;

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('audit-root'))),
        ),
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

    // The server's projection after end-early: version 4, past the 3 the
    // restored trip was seeded with.
    final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
    realtime.emit(RideStatus.cancelledByRider, sequence: 4);
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.byType(RideCompleted), findsOneWidget);
    expect(find.text('Trip ended early'), findsOneWidget);
    expect(find.text('You pay 80 kr'), findsOneWidget);
    expect(find.text('80 kr'), findsOneWidget);
  });
}
