import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner, live test 2026-10-26: when the driver finishes the trip while the
/// rider app is closed, opening it shows the finished-trip / tip screen;
/// then it goes Home by itself and the trip is only in History. A phone
/// that never saw the trip (another device, cleared storage) opened Home
/// and never offered the screen; and closing it never told the server, so
/// nothing could tell "seen" from "not seen" across phones.
const _staging = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.staging.movera.invalid',
);

Map<String, dynamic> _trip({
  String ratingStatus = 'pending',
  required DateTime updatedAt,
}) => {
  'tripId': 'trp_done',
  'status': 'completed',
  'paymentStatus': 'captured',
  'ratingStatus': ratingStatus,
  'version': 9,
  'kind': 'live',
  'categoryId': 'economy',
  'paymentMethod': 'cash',
  'fare': {'amountMinor': 5400, 'currency': 'SEK'},
  'pickup': {'address': 'Södertälje C', 'lat': 59.1955, 'lng': 17.6253},
  'dropoff': {'address': 'Hamngatan 1', 'lat': 59.3326, 'lng': 18.0649},
  'createdAt': updatedAt
      .subtract(const Duration(minutes: 20))
      .toUtc()
      .toIso8601String(),
  'updatedAt': updatedAt.toUtc().toIso8601String(),
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

ApiActiveTripRepository _repo(List<Map<String, dynamic>> items, {
  List<Uri>? asked,
}) => ApiActiveTripRepository(
  api: ApiClient(
    env: _staging,
    client: MockClient((request) async {
      asked?.add(request.url);
      return _json({'items': items, 'nextCursor': null});
    }),
  ),
);

class _Realtime implements RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast(sync: true);
  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _events.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void researchAfterDriverCancel() {}
  @override
  void dispose() => _events.close();
}

class _Complete extends RideCompleteController {
  final skipped = <String>[];
  final closed = <String>[];
  @override
  Future<void> closeCompletedRide(String rideId) async => closed.add(rideId);
  @override
  Future<void> skipRating({
    required String rideId,
    required String idempotencyKey,
  }) async => skipped.add(rideId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  group('the last finished trip from the server', () {
    test('finished 10 min ago and not rated: offered for rating', () async {
      final asked = <Uri>[];
      final now = DateTime.now();
      final trip = await _repo(
        [_trip(updatedAt: now.subtract(const Duration(minutes: 10)))],
        asked: asked,
      ).fetchRecentlyFinished(now: now);
      expect(trip?.rideId, 'trp_done');
      expect(trip?.status.isCompletedSurface, isTrue);
      expect(trip?.destinationAddress, 'Hamngatan 1');
      expect(asked.single.path, '/api/v1/rider/trips');
      expect(asked.single.queryParameters['status'], 'completed');
      expect(asked.single.queryParameters['limit'], '1');
    });

    test('rated or skipped already: nothing to show', () async {
      final now = DateTime.now();
      for (final status in ['submitted', 'skipped']) {
        expect(
          await _repo([
            _trip(ratingStatus: status, updatedAt: now),
          ]).fetchRecentlyFinished(now: now),
          isNull,
          reason: status,
        );
      }
    });

    test('finished more than 6 h ago, or no trip: nothing to show', () async {
      final now = DateTime.now();
      expect(
        await _repo([
          _trip(updatedAt: now.subtract(const Duration(hours: 7))),
        ]).fetchRecentlyFinished(now: now),
        isNull,
      );
      expect(await _repo([]).fetchRecentlyFinished(now: now), isNull);
    });
  });

  group('opening the app with no trip stored on this phone', () {
    RideSnapshot finished() => RideSnapshot(
      rideId: 'trp_done',
      status: RideStatus.ratingPending,
      savedAt: DateTime.now(),
      pickupAddress: 'Södertälje C',
      destinationAddress: 'Hamngatan 1',
      pickupLat: 59.1955,
      pickupLng: 17.6253,
      destinationLat: 59.3326,
      destinationLng: 18.0649,
      rideType: 'Movera',
      price: 54,
      paymentMethod: 'Cash',
    );

    test('the finished-trip screen opens for a trip finished while closed',
        () async {
      final restore = RideRestoreCoordinator(
        resync: (_) async {},
        authRequired: () => false,
        serverActiveTrip: () async => null,
        serverRecentlyFinished: () async => finished(),
      );
      final page = await restore.root();
      expect(page, isA<RideCompleted>());
      expect((page as RideCompleted).rideId, 'trp_done');
      expect(restore.showing, RestoredSurface.complete);
      expect((await RideSnapshotStore.read())?.rideId, 'trp_done');
    });

    test('a live trip wins over a finished one', () async {
      final restore = RideRestoreCoordinator(
        resync: (_) async {},
        authRequired: () => false,
        serverActiveTrip: () async =>
            finished().copyWith(status: RideStatus.findingDriver),
        serverRecentlyFinished: () async => finished(),
      );
      expect(await restore.root(), isA<FindingDrivers>());
    });
  });

  test('skip sends RatingRequest {skip: true} on the live wire', () async {
    final sent = <http.Request>[];
    final repo = RideFeedbackRepository(
      api: ApiClient(
        env: _staging,
        client: MockClient((request) async {
          sent.add(request);
          return _json({'tripId': 'trp_done'}, 201);
        }),
      ),
    );
    await repo.skip(rideId: 'trp_done', idempotencyKey: 'k1');
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/api/v1/trips/trp_done/rating');
    expect(jsonDecode(sent.single.body), {'skip': true});
  });

  testWidgets('leaving without a rating skips it, so no phone offers the '
      'screen again', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = _Complete();
    final realtime = _Realtime();
    addTearDown(realtime.dispose);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(1200, 1600),
      builder: (_, __) => MaterialApp(
        home: RideCompleted(
          status: RideStatus.ratingPending,
          rideId: 'trp_done',
          realtime: realtime,
          controller: controller,
        ),
      ),
    ));
    await tester.pump();
    // The 2 minutes run out without a touch.
    await tester.pump(RideCompleted.defaultAutoCloseAfter);
    await tester.pump();
    expect(controller.skipped, ['trp_done']);
    expect(controller.closed, ['trp_done']);
  });
}
