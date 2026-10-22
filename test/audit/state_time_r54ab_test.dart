import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/presentation/rider_name.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

/// Wave 5 R5.4 parts a + b: state and time (low). One test per bug.
const _env = AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://x.invalid');

/// Books a ride on the in-process stand-in server and returns its id.
Future<String> _book(ApiClient api) async {
  const at = {
    'pickupLat': 59.3293,
    'pickupLng': 18.0686,
    'destinationLat': 59.3326,
    'destinationLng': 18.0649,
  };
  final quote = (await api.post(
    '/api/v1/quotes',
    body: {'rideType': 'economy', ...at},
  ))['quote'] as Map;
  final created = await api.post(
    '/api/v1/rides',
    body: {
      'categoryId': 'economy',
      'fare': {'amountMinor': quote['totalMinor'], 'currency': 'SEK'},
      'paymentMethodId': 'card',
      'pickupAddress': 'Pickup',
      'destinationAddress': 'Destination',
      ...at,
      'quoteId': quote['id'],
      'quoteSignedPayload': quote['signedPayload'],
      'quoteExpiresAt': quote['expiresAt'],
      'quoteTotalMinor': quote['totalMinor'],
    },
  );
  return (created['ride'] as Map)['id'] as String;
}

/// Waits (on the event loop, no fixed delay) until [done] holds.
Future<void> _until(bool Function() done, {int turns = 500}) async {
  for (var i = 0; i < turns && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'condition never held');
}

/// A demo transport resumed at [status] for a pickup at Stockholm city.
(MockRideRealtime, List<RideRealtimeEvent>) _resumedDemo(RideStatus status) {
  final rt = MockRideRealtime(tripTick: const Duration(seconds: 3));
  rt.primeResume(status: status, pickupLat: 59.33, pickupLng: 18.06);
  final events = <RideRealtimeEvent>[];
  rt.subscribe('ride_demo').listen(events.add);
  return (rt, events);
}

/// A map controller that only records camera moves.
class _FakeMap extends Fake implements GoogleMapController {
  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rider-6: a wrong OTP with an old token left is a wrong code, not an '
      'expired session', () async {
    final tokens = MemoryTokenStore();
    await tokens.save(access: 'old-access', refresh: 'mock-refresh-1');
    var expired = 0;
    var refreshes = 0;
    final api = ApiClient(
      env: _env,
      tokens: tokens,
      onSessionExpired: () async => expired++,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          return http.Response(
            jsonEncode({'accessToken': 'new', 'refreshToken': 'r2'}),
            200,
          );
        }
        return http.Response(jsonEncode({'code': 'invalid_otp'}), 401);
      }),
    );
    await expectLater(
      api.post('/api/v1/auth/otp/verify', body: {'code': '000000'}),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'invalid_otp')),
    );
    expect(expired, 0);
    expect(refreshes, 0);
    expect(await tokens.readAccess(), 'old-access');
  });

  test('rider-8: an offer raise while searching is a committed change',
      () async {
    final server = InProcessMockClient();
    final api = ApiClient(client: server);
    final id = await _book(api);
    final before = Map<String, dynamic>.of(server.rides[id]!);
    await api.patch('/api/v1/rides/$id', body: {
      'offerIncrease': {'amountMinor': 5000, 'currency': 'SEK'},
    });
    final after = server.rides[id]!;
    expect(after['fare'], isNot(before['fare']));
    expect(after['version'], (before['version'] as int) + 1);
    expect(after['eventId'], isNot(before['eventId']));
  });

  test('rider-j8-13: a web flight stopped by a tap leaves the pose where the '
      'camera stopped', () async {
    const start = CameraPosition(target: LatLng(59.30, 18.00), zoom: 13);
    const goal = CameraPosition(target: LatLng(59.40, 18.10), zoom: 15);
    const midway = CameraPosition(target: LatLng(59.35, 18.05), zoom: 14);
    RiderMapBridge.debugFlight = (_, _, _) => Completer<bool>().future;
    RiderMapBridge.debugCancelFlight = (_) => midway;
    addTearDown(() {
      RiderMapBridge.debugFlight = null;
      RiderMapBridge.debugCancelFlight = null;
    });
    final map = _FakeMap();
    final view = mapViewOf(map)
      ..mapId = 1
      ..pose = start;
    unawaited(easeCameraTo(map, goal, duration: cameraFlightDuration));
    expect(view.easing, isTrue);
    view.touching = true; // the tap stops the flight
    expect(view.pose, midway);
  });

  test('rider-u26: a driver drop re-offered within one poll is still the '
      'driver-cancelled notice', () async {
    final server = InProcessMockClient();
    final api = ApiClient(client: server);
    final id = await _book(api);
    Future<void> simulate(Map<String, dynamic> body) =>
        api.post('/api/v1/rides/$id/status', body: body);
    await simulate({'status': 'driver_to_pickup'});
    final realtime = ApiRideRealtime(
      api: api,
      pollInterval: const Duration(days: 1),
    );
    addTearDown(realtime.dispose);
    final events = <RideRealtimeEvent>[];
    final sub = realtime.subscribe(id).listen(events.add);
    addTearDown(sub.cancel);
    await _until(() => events.isNotEmpty);
    await simulate({'command': 'cancel', 'actor': 'driver'});
    await simulate({'command': 'send_offer', 'actor': 'system'});
    final seen = events.length;
    await realtime.reconnectAndResync(id);
    await _until(() => events.length > seen);
    expect(events.last.isAdminReassign, isFalse);
    expect(events.last.kind, RealtimeKind.driverCancelled);
  });

  testWidgets('rider-u30: the demo driver drives to a pickup moved after the '
      'accept', (tester) async {
    final (rt, events) = _resumedDemo(RideStatus.driverArriving);
    await tester.pump();
    rt.movePickup(59.335, 18.07);
    for (var i = 0; i < 100 && rt.lastStatus != RideStatus.driverWaiting; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    final arrived = events.lastWhere(
      (e) => e.signal == RideRealtimeSignal.driverArrived,
    );
    expect(
      GeoDistance.metersBetween(
        arrived.latitude!,
        arrived.longitude!,
        59.335,
        18.07,
      ),
      lessThan(50),
    );
    rt.dispose();
  });

  testWidgets('rider-u31: in the trip the demo ETA counts down to the '
      'destination', (tester) async {
    final (rt, events) = _resumedDemo(RideStatus.tripInProgress);
    rt
      ..destinationLat = 59.36
      ..destinationLng = 18.10;
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    final etas = [
      for (final e in events)
        if (e.status == RideStatus.tripInProgress && e.etaSeconds != null)
          e.etaSeconds!,
    ];
    expect(etas.length, greaterThan(2));
    expect(etas.last, lessThan(etas.first));
    rt.dispose();
  });

  test('rider-25: History keeps the completion time when Done comes later',
      () async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    final trip = RideSnapshot(
      status: RideStatus.tripInProgress,
      savedAt: DateTime.now(),
      pickupAddress: 'A',
      destinationAddress: 'B',
      pickupLat: 59.33,
      pickupLng: 18.06,
      destinationLat: 59.34,
      destinationLng: 18.07,
      rideType: 'Movera',
      price: 259,
      paymentMethod: 'Apple Pay',
      rideId: 'ride_r25',
    );
    await RideSnapshotStore.save(trip);
    AppScope.instance.ride
      ..rideId = trip.rideId
      ..status = RideStatus.tripInProgress;
    final controller = ActiveRideController();
    await controller.markCompleted(RideStatus.tripCompleted);
    // The rider stayed on the summary for 40 minutes before Done.
    final completedAt = DateTime.now().subtract(const Duration(minutes: 40));
    final stored = (await RideSnapshotStore.read())!;
    await RideSnapshotStore.save(stored.copyWith(completedAt: completedAt));
    await controller.closeCompletedRide('ride_r25');
    final record = (await OnDemandRideHistoryStore.read()).single;
    expect(
      record.scheduledPickupAt.difference(completedAt).inSeconds.abs(),
      lessThan(2),
    );
  });

  test('rider-u60: a stop the rider added moves the pre-trip arrival '
      'estimate', () {
    const pickup = GeoPoint(59.33, 18.06);
    const destination = GeoPoint(59.33, 18.16);
    // About 5 km north of the direct line.
    const stop = GeoPoint(59.375, 18.11);
    final direct = estimatedRouteMinutes(pickup, const [], destination);
    expect(direct, estimatedTripMinutes(pickup, destination));
    expect(
      estimatedRouteMinutes(pickup, const [stop], destination),
      greaterThan(direct + 5),
    );
  });

  test('rider-u68: a flush still running after the sign-out wipe writes '
      'nothing back', () async {
    SharedPreferences.setMockInitialValues({});
    await PendingCancelStore.enqueue(rideId: 'ride_u68', expectedVersion: 1);
    final reread = Completer<http.Response>();
    var gets = 0;
    var posts = 0;
    final api = ApiClient(
      env: _env,
      client: MockClient((request) {
        if (request.method == 'GET') {
          gets++;
          return reread.future;
        }
        posts++;
        return Future.value(http.Response('{"code":"OK"}', 200));
      }),
    );
    final flush = FindingDriverController.flushPendingCancels(api: api);
    await _until(() => gets == 1);
    await UserDataWipe.run();
    reread.complete(http.Response(
      jsonEncode({
        'ride': {'id': 'ride_u68', 'status': 'searching', 'version': 2},
      }),
      200,
    ));
    await flush;
    expect(await PendingCancelStore.all(), isEmpty);
    expect(posts, 0);
  });

  test('rider-u74: a reload on the new-rider name step asks for the name '
      'again', () async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    final auth = AuthRepository(
      tokens: MemoryTokenStore(),
      api: ApiClient(
        env: _env,
        client: MockClient((_) async => http.Response(
          jsonEncode({
            'accessToken': 'a',
            'refreshToken': 'r',
            'isNewRider': true,
          }),
          200,
        )),
      ),
    );
    final result = await auth.verifyOtp(
      challenge: OtpChallenge(
        phone: '+46700000000',
        requestId: 'q',
        sessionId: 's',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        retryAfter: Duration.zero,
      ),
      code: '1234',
    );
    expect(result.isNewRider, isTrue);
    // The page reloads before the rider types a name.
    final page = await RideRestoreCoordinator(
      skipRestore: () => false,
      authRequired: () => false,
      serverActiveTrip: () async => null,
    ).root();
    expect(page, isA<RiderNameScreen>());
  });
}
