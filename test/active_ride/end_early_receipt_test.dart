import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R-UI UI-01: on board, "Cancel ride" sent `POST …/end-early` (contract:
/// "Pays distance driven"), but the rider was never told they pay, got no
/// amount and no receipt, landed on Home, and History said "Cancelled ride ·
/// Booked price". The trip now ends like a finish: a summary with what the
/// server says they pay, and History reads "Ended early" with that price.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const rideId = 'ride_end_early_1';
  final paths = <String>[];

  ApiClient api({Map<String, dynamic>? fare}) => ApiClient(
    client: MockClient((request) async {
      paths.add('${request.method} ${request.url.path}');
      return http.Response(
        jsonEncode({
          'code': 'OK',
          'ride': {
            'tripId': rideId,
            'status': 'cancelled_by_rider',
            'fare': ?fare,
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    LastCompletedRide.clear();
    paths.clear();
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..restoreFromBackend(RideStatus.tripInProgress, id: rideId);
    await RideSnapshotStore.save(
      RideSnapshot(
        status: RideStatus.tripInProgress,
        savedAt: DateTime.now(),
        pickupAddress: 'Sveavägen 1',
        destinationAddress: 'Stockholm Arlanda Airport',
        pickupLat: 59.34,
        pickupLng: 18.05,
        destinationLat: 59.65,
        destinationLng: 17.93,
        rideType: 'Movera',
        price: 659,
        paymentMethod: 'Apple Pay',
        rideId: rideId,
      ),
    );
  });

  test('end-early keeps what the rider pays for the receipt and History',
      () async {
    final controller = ActiveRideController(
      api: api(fare: {'amountMinor': 24500, 'currency': 'SEK'}),
    );
    final outcome = await controller.markCancelled(reasonId: 'plans_changed');

    expect(outcome, RideCancelOutcome.confirmed);
    expect(paths.single, 'POST /api/v1/rides/$rideId/end-early');
    expect(controller.endedEarly?.rideId, rideId);
    expect(controller.endedEarly?.charged, const Money(24500));
    expect(LastCompletedRide.charged, const Money(24500));
    expect(AppScope.instance.rideComplete.receipt()?.total, '245 kr');

    final history = await OnDemandRideHistoryStore.read();
    final record = history.single;
    expect(record.endedEarly, isTrue);
    expect(record.chargedFare, const Money(24500));
    expect(ReservationFormat.historyStatus(record), 'Ended early');
    expect(ReservationFormat.price(record), '245 kr');
    expect(ReservationFormat.reasonLabel(record.cancellationReason!),
        'Plans changed');
  });

  test('a cancel before boarding is not an ended-early trip', () async {
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverArriving,
      id: rideId,
    );
    final controller = ActiveRideController(api: api());
    await controller.markCancelled();

    expect(paths.single, 'POST /api/v1/rides/$rideId/cancel');
    expect(controller.endedEarly, isNull);
    final record = (await OnDemandRideHistoryStore.read()).single;
    expect(record.endedEarly, isFalse);
    expect(ReservationFormat.historyStatus(record), 'Cancelled');
  });

  testWidgets('the ended-early summary says what the rider pays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ActiveRideController(
      api: api(fare: {'amountMinor': 24500, 'currency': 'SEK'}),
    );
    await tester.runAsync(() => controller.markCancelled());
    var closed = false;

    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) => MaterialApp(
          home: RideCompleted(
            status: RideStatus.cancelledByRider,
            rideId: rideId,
            endedEarly: controller.endedEarly,
            persistOnDemandState: false,
            showConnectionBanner: false,
            onClose: (_) async => closed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Trip ended early'), findsOneWidget);
    expect(find.text('You pay 245 kr'), findsOneWidget);
    expect(find.textContaining('distance driven'), findsWidgets);
    expect(find.text('Total payment'), findsOneWidget);
    expect(find.text('245 kr'), findsOneWidget);
    // R-O6 (owner decision): the normal trip-end screen, rating included.
    expect(find.byKey(const ValueKey('completion-feedback')), findsOneWidget);
    expect(find.text('Ended early'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ride-completed-done')));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('History shows Ended early instead of a driver badge', (
    tester,
  ) async {
    final controller = ActiveRideController(
      api: api(fare: {'amountMinor': 24500, 'currency': 'SEK'}),
    );
    await tester.runAsync(() => controller.markCancelled());
    final record = (await tester.runAsync(OnDemandRideHistoryStore.read))!
        .single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReservationHistoryCard(ride: record, onTap: () {}),
        ),
      ),
    );
    expect(find.text('Ended early'), findsOneWidget);
    expect(find.text('245 kr'), findsOneWidget);
    expect(find.text('Driver pending'), findsNothing);
    expect(find.text('Driver assigned'), findsNothing);
  });
}
