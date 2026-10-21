import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/mock_catalog_fares.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner decisions on the rider open items:
/// - R-O1 / R-O7: an ended-early trip costs base fare + km driven × the
///   category's per-km rate, in the app's stand-in server too;
/// - R-O6: the rider then gets the normal trip-end screen with rating, and
///   its waybill says "Ended early" with the km driven;
/// - R-O3: a second cancel of a cancelled trip is quietly OK;
/// - R-O4: the stand-in server answers with the contract's lower-case codes;
/// - R-O2: commands carry `expectedVersion` (the projection version, not
///   the realtime sequence); a stale tap is refused and the rider is told
///   "Your ride just changed, check it again"; an outbox replay reads the
///   trip first and is neither refused spuriously nor sent when it no
///   longer applies.

/// `contract.json#errors.codes`.
const _contractCodes = {
  'invalid_request',
  'unauthenticated',
  'forbidden',
  'not_found',
  'conflict',
  'invalid_transition',
  'version_mismatch',
  'rate_limited',
  'unavailable',
  'internal',
};

const _pickup = (lat: 59.3293, lng: 18.0686);

class _Feed implements RideRealtime {
  final StreamController<RideRealtimeEvent> events =
      StreamController<RideRealtimeEvent>.broadcast();
  final resyncs = <String>[];

  @override
  bool get supportsRiderSignals => false;

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => events.stream;

  @override
  Future<void> reconnectAndResync(String rideId) async => resyncs.add(rideId);

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
  void dispose() => unawaited(events.close());
}

/// A request the scripted server saw.
class _Seen {
  _Seen(this.method, this.path, this.body, this.key);
  final String method;
  final String path;
  final Map<String, dynamic> body;
  final String? key;
}

ApiClient _scripted(
  List<_Seen> seen,
  http.Response Function(_Seen request) answer,
) => ApiClient(
  client: MockClient((request) async {
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(request.body) as Map);
    final entry = _Seen(
      request.method,
      request.url.path,
      body,
      request.headers['Idempotency-Key'],
    );
    seen.add(entry);
    return answer(entry);
  }),
  env: AppEnv.current,
);

http.Response _json(int status, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), status);

/// openapi CancelCommand requires a reasonCode (rider-u19).
const _reason = {'reasonCode': 'plans_changed'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late InProcessMockClient server;
  late ApiClient api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    LastCompletedRide.clear();
    server = InProcessMockClient();
    api = ApiClient(client: server);
  });

  Future<String> book({
    String category = 'economy',
    double destinationLat = 59.40,
    double destinationLng = 18.10,
  }) async {
    final quote = (await api.post(
      '/api/v1/quotes',
      body: {
        'rideType': category,
        'pickupLat': _pickup.lat,
        'pickupLng': _pickup.lng,
        'destinationLat': destinationLat,
        'destinationLng': destinationLng,
      },
    ))['quote'] as Map;
    final created = await api.post(
      '/api/v1/rides',
      body: {
        'categoryId': category,
        'price': (quote['totalMinor'] as int) / 100,
        'paymentMethodId': 'cash',
        'pickupAddress': 'Pickup',
        'destinationAddress': 'Destination',
        'pickupLat': _pickup.lat,
        'pickupLng': _pickup.lng,
        'destinationLat': destinationLat,
        'destinationLng': destinationLng,
        'quoteId': quote['id'],
        'quoteSignedPayload': quote['signedPayload'],
        'quoteExpiresAt': quote['expiresAt'],
        'quoteTotalMinor': quote['totalMinor'],
      },
    );
    return (created['ride'] as Map)['id'] as String;
  }

  Future<Map<String, dynamic>> simulate(
    String id,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    (await api.post('/api/v1/rides/$id/status', body: body))['ride'] as Map,
  );

  /// The driver starts the trip at pickup and drives north [km] km in
  /// one-kilometre fixes.
  Future<void> drive(String id, int km) async {
    await simulate(id, {
      'status': 'in_trip',
      'lat': _pickup.lat,
      'lng': _pickup.lng,
    });
    for (var i = 1; i <= km; i++) {
      await simulate(id, {'lat': _pickup.lat + 0.009 * i, 'lng': _pickup.lng});
    }
  }

  Future<ApiError> refused(Future<Object?> call) async {
    try {
      await call;
    } on ApiError catch (error) {
      return error;
    }
    fail('expected an ApiError');
  }

  group('R-O1 / R-O7: the end-early price in the stand-in server', () {
    test('base fare + km driven × the category per-km rate, as Money',
        () async {
      final id = await book();
      final booked = server.rides[id]!['fare'] as Map;
      await drive(id, 2);
      final meters = server.drivenMetersOf(id);
      expect(meters, closeTo(2000, 10));

      final ended = (await api.post(
        '/api/v1/rides/$id/end-early',
        body: {'expectedVersion': server.rides[id]!['version']},
      ))['ride'] as Map;

      // economy lists at 259 kr for 3 km at 12 kr/km: base 223 kr.
      final rates = MockCategoryRates(catalogMajor: mockCatalogPricesKr['economy']!);
      expect(rates.baseMajor, 223);
      final expected = 22300 + (meters * 1200 + 500) ~/ 1000;
      expect(ended['status'], 'cancelled_by_rider');
      expect(ended['fare'], {'amountMinor': expected, 'currency': 'SEK'});
      expect(expected, lessThan(booked['amountMinor'] as int));
      expect(ended['fareLines'], [
        {
          'code': 'base',
          'amount': {'amountMinor': 22300, 'currency': 'SEK'},
        },
        {
          'code': 'distance',
          'amount': {'amountMinor': expected - 22300, 'currency': 'SEK'},
        },
      ]);
      // End-early is not a cancel fee.
      expect((ended['cancellation'] as Map)['fee'], isNull);
    });

    test('a pricier category has its own base fare', () async {
      final id = await book(category: 'premium');
      await drive(id, 1);
      final meters = server.drivenMetersOf(id);
      final ended = (await api.post('/api/v1/rides/$id/end-early'))['ride']
          as Map;
      // premium lists at 369 kr: base 333 kr.
      expect(
        (ended['fare'] as Map)['amountMinor'],
        33300 + (meters * 1200 + 500) ~/ 1000,
      );
    });

    test('fixes before boarding are not driven distance', () async {
      final id = await book();
      await simulate(id, {'status': 'driver_to_pickup', 'lat': 59.30, 'lng': 18.0});
      await simulate(id, {'lat': 59.31, 'lng': 18.0});
      expect(server.drivenMetersOf(id), 0);
    });

    test('never more than the agreed fare', () async {
      final id = await book(destinationLat: 59.335, destinationLng: 18.07);
      final booked = (server.rides[id]!['fare'] as Map)['amountMinor'] as int;
      await drive(id, 20);
      final ended = (await api.post('/api/v1/rides/$id/end-early'))['ride']
          as Map;
      expect((ended['fare'] as Map)['amountMinor'], booked);
    });

    test('a TND amount uses three decimals', () {
      const rates = MockCategoryRates(catalogMajor: 50);
      expect(rates.baseFare('TND'), const Money(14000, 'TND'));
      expect(rates.distanceFare(1500, 'TND'), const Money(18000, 'TND'));
      expect(rates.distanceFare(1500, 'SEK'), const Money(1800, 'SEK'));
    });

    test('quotes keep their formula', () {
      const rates = MockCategoryRates(catalogMajor: 259);
      expect(rates.quoteMajor(3000), 259);
      expect(rates.quoteMajor(8000), 319);
      expect(rates.quoteMajor(0), 223);
    });
  });

  group('R-O6: the ended-early trip is rated on the normal screen', () {
    test('the server accepts a rating for it, not for a plain cancel',
        () async {
      final ended = await book();
      await drive(ended, 1);
      await api.post('/api/v1/rides/$ended/end-early');
      expect(server.rides[ended]!['ratingStatus'], 'pending');
      final feedback = RideFeedbackRepository(api: api);
      await feedback.submit(rideId: ended, rating: 4, idempotencyKey: 'fb-1');
      expect(server.rides[ended]!['ratingStatus'], 'submitted');

      final cancelled = await book();
      await api.post('/api/v1/rides/$cancelled/cancel', body: _reason);
      final error = await refused(
        feedback.submit(rideId: cancelled, rating: 4, idempotencyKey: 'fb-2'),
      );
      expect(error.code, 'invalid_transition');
    });

    testWidgets('rating on, waybill says Ended early with the km driven', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late String id;
      await tester.runAsync(() async {
        id = await book();
        await drive(id, 2);
        await api.post('/api/v1/rides/$id/end-early');
      });
      final fare = Money.fromWire(server.rides[id]!['fare'])!;
      final trip = EndedEarlyTrip(rideId: id, charged: fare, drivenMeters: 2400);
      LastCompletedRide.remember(
        RideSnapshot(
          status: RideStatus.tripInProgress,
          savedAt: DateTime.now(),
          pickupAddress: 'Pickup',
          destinationAddress: 'Destination',
          pickupLat: _pickup.lat,
          pickupLng: _pickup.lng,
          destinationLat: 59.40,
          destinationLng: 18.10,
          rideType: 'Movera',
          price: 319,
          paymentMethod: 'Cash',
          rideId: id,
        ),
        charged: fare,
        endedEarly: true,
        drivenMeters: trip.drivenMeters,
      );
      var closed = false;
      await tester.pumpWidget(
        MoveraScreenUtilInit(
          builder: (_, __) => MaterialApp(
            home: RideCompleted(
              status: RideStatus.cancelledByRider,
              rideId: id,
              endedEarly: trip,
              persistOnDemandState: false,
              showConnectionBanner: false,
              controller: RideCompleteController(
                feedback: RideFeedbackRepository(api: api),
              ),
              onClose: (_) async => closed = true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Trip ended early'), findsOneWidget);
      expect(find.text('How was your trip'), findsOneWidget);
      final lock = tester.widget<IgnorePointer>(
        find.byKey(const ValueKey('completion-feedback-lock')),
      );
      expect(lock.ignoring, isFalse, reason: 'the rider can rate it');
      expect(find.text('Ended early'), findsOneWidget);
      expect(find.text('2.4 km driven'), findsOneWidget);
      expect(find.text('Total payment'), findsOneWidget);
      expect(find.text('You pay ${formatMoney(fare)}'), findsOneWidget);

      final star = find.byIcon(Icons.star_rounded).last;
      await tester.ensureVisible(star);
      await tester.tap(star);
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('ride-completed-done')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(closed, isTrue);
      expect(server.rides[id]!['ratingStatus'], 'submitted');
    });
  });

  group('R-O3: a second cancel is quietly OK', () {
    test('the server: 200, no second fee, nothing changes', () async {
      final id = await book();
      await simulate(id, {'status': 'accepted'});
      final first = (await api.post(
        '/api/v1/rides/$id/cancel',
        body: {'reasonCode': 'plans_changed'},
      ))['ride'] as Map;
      final version = first['version'];
      final fee = (first['cancellation'] as Map)['fee'];

      // Even with the version the rider's stale screen still had.
      final again = (await api.post(
        '/api/v1/rides/$id/cancel',
        body: {'expectedVersion': 1, 'reasonCode': 'plans_changed'},
      ))['ride'] as Map;
      expect(again['status'], 'cancelled_by_rider');
      expect(again['version'], version);
      expect((again['cancellation'] as Map)['fee'], fee);
      expect(server.rides[id]!['cancellation'], first['cancellation']);
    });

    test('the app shows it as cancelled, also after a 409 that says so',
        () async {
      final id = await book();
      await simulate(id, {'status': 'accepted'});
      await api.post('/api/v1/rides/$id/cancel', body: _reason);
      final ride = AppScope.instance.ride
        ..rideId = null
        ..suppressRestore = false
        ..restoreFromBackend(RideStatus.driverArriving, id: id);
      ride.observeProjectionVersion(id, 2);
      expect(
        await ActiveRideController(api: api).markCancelled(),
        RideCancelOutcome.confirmed,
      );
      expect(AppScope.instance.ride.status, RideStatus.cancelledByRider);

      // A server that answers a second cancel with 409 and the cancelled
      // trip: still just cancelled, sent once.
      final seen = <_Seen>[];
      AppScope.instance.ride
        ..rideId = null
        ..suppressRestore = false
        ..restoreFromBackend(RideStatus.driverArriving, id: 'twice');
      final outcome = await ActiveRideController(
        api: _scripted(seen, (_) => _json(409, {
          'code': 'invalid_transition',
          'message': 'cancel is not allowed',
          'retryable': false,
          'projection': {
            'tripId': 'twice',
            'status': 'cancelled_by_rider',
            'version': 9,
          },
        })),
      ).markCancelled();
      expect(outcome, RideCancelOutcome.confirmed);
      expect(seen, hasLength(1));
      expect(await PendingCancelStore.all(), isEmpty);
    });

    test('Finding: a second cancel is confirmed', () async {
      final id = await book();
      await api.post('/api/v1/rides/$id/cancel', body: _reason);
      final feed = _Feed();
      addTearDown(feed.dispose);
      final session = RideSession()
        ..rideId = id
        ..status = RideStatus.findingDriver;
      final controller = FindingDriverController(
        realtime: feed,
        ride: session,
        api: api,
      );
      addTearDown(controller.dispose);
      controller.start(
        snapshot: RideSnapshot(
          status: RideStatus.findingDriver,
          savedAt: DateTime.now(),
          pickupAddress: 'Pickup',
          destinationAddress: 'Destination',
          pickupLat: _pickup.lat,
          pickupLng: _pickup.lng,
          destinationLat: 59.40,
          destinationLng: 18.10,
          rideType: 'Movera',
          price: 319,
          paymentMethod: 'Cash',
          rideId: id,
        ),
        onTick: (_) {},
        onMatched: () {},
        onTerminal: (_) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await controller.cancelSearch(), SearchCancelResult.confirmed);
      expect(controller.cancelled, isTrue);
    });
  });

  group('R-O4: contract error codes', () {
    test('every refusal of the stand-in server uses a contract code',
        () async {
      final id = await book();
      final errors = <ApiError>[
        await refused(api.get('/api/v1/rides/nope')),
        await refused(api.post('/api/v1/rides/nope/cancel')),
        await refused(api.post('/api/v1/rides/$id/feedback', body: {'rating': 5})),
        await refused(api.post('/api/v1/payments', body: {'amountMinor': -1})),
        await refused(api.get('/api/v1/no-such-route')),
        await refused(api.post(
          '/api/v1/auth/otp/verify',
          body: {'sessionId': 'x', 'phone': '+46701234567', 'code': '1'},
        )),
        await refused(api.post('/api/v1/auth/otp/request', body: {})),
        await refused(api.post(
          '/api/v1/rides/$id/cancel',
          body: {'reasonCode': 'admin_fraud'},
        )),
        await refused(api.post(
          '/api/v1/rides',
          body: {'pickupAddress': 'A', 'quoteId': 'missing'},
        )),
      ];
      for (final error in errors) {
        expect(_contractCodes, contains(error.code), reason: '$error');
        expect(error.code, error.code.toLowerCase());
      }
      expect(errors.first.code, 'not_found');
      expect(errors[2].code, 'invalid_transition');
      expect(errors[2].projection?['tripId'], id);
      expect(errors[5].reason, 'invalid_otp_session');
      expect(errors[8].code, 'conflict');
      expect(errors[8].reason, 'quote_required');
    });

    test('the app still tells the specific sign-in problem', () async {
      final error = await refused(api.post(
        '/api/v1/auth/otp/verify',
        body: {'sessionId': 'gone', 'phone': '+46701234567', 'code': '1234'},
      ));
      expect(
        authErrorMessage(error, AuthAction.verifyCode),
        'This code has expired. Tap Resend code for a new one.',
      );
      final phone = await refused(
        api.post('/api/v1/auth/otp/request', body: {'phone': ''}),
      );
      expect(
        authErrorMessage(phone, AuthAction.sendCode),
        'Enter a valid Swedish mobile number.',
      );
    });

    test('a route change the stage no longer allows', () async {
      final id = await book();
      await simulate(id, {'status': 'completed'});
      final error = await refused(api.post(
        '/api/v1/rides/$id/route-quote',
        body: {'destinationAddress': 'X', 'stops': []},
      ));
      expect(error.code, 'invalid_transition');
      expect(error.reason, 'ride_finished');
    });
  });

  group('R-O2: expectedVersion', () {
    test('cancel sends the projection version, not the realtime sequence',
        () async {
      final seen = <_Seen>[];
      AppScope.instance.ride
        ..rideId = null
        ..suppressRestore = false
        // Realtime ordering (sequence-based) far ahead of the version.
        ..backendReconcile(RideStatus.driverArriving, id: 'v-seq', version: 41)
        ..observeProjectionVersion('v-seq', 6);
      await ActiveRideController(
        api: _scripted(seen, (_) => _json(200, {
          'tripId': 'v-seq',
          'status': 'cancelled_by_rider',
          'version': 7,
        })),
      ).markCancelled(reasonId: 'plans_changed');
      expect(seen.single.path, '/api/v1/rides/v-seq/cancel');
      expect(seen.single.body['expectedVersion'], 6);
      expect(AppScope.instance.ride.projectionVersionOf('v-seq'), 7);
    });

    test('end-early sends it too, and keeps the km the app tracked',
        () async {
      final id = await book();
      await drive(id, 2);
      AppScope.instance.ride
        ..rideId = null
        ..suppressRestore = false
        ..restoreFromBackend(RideStatus.tripInProgress, id: id)
        ..observeProjectionVersion(id, server.rides[id]!['version']);
      final controller = ActiveRideController(api: api);
      expect(
        await controller.markCancelled(drivenMeters: 1980),
        RideCancelOutcome.confirmed,
      );
      expect(controller.endedEarly?.drivenMeters, 1980);
      expect(
        controller.endedEarly?.charged,
        Money.fromWire(server.rides[id]!['fare']),
      );
      expect(server.rides[id]!['status'], 'cancelled_by_rider');
    });

    test('the owner case: the driver started the trip a second before the '
        'cancel tap', () async {
      final id = await book();
      await simulate(id, {'status': 'arrived'});
      final seenVersion = server.rides[id]!['version'] as int;
      AppScope.instance.ride
        ..rideId = null
        ..suppressRestore = false
        ..restoreFromBackend(RideStatus.driverWaiting, id: id)
        ..observeProjectionVersion(id, seenVersion);
      // The driver starts the trip; the rider's screen has not caught up.
      await simulate(id, {'status': 'rider_onboard'});

      final counting = _CountingClient(server);
      final outcome = await ActiveRideController(
        api: ApiClient(client: counting),
      ).markCancelled(reasonId: 'plans_changed');

      expect(outcome, RideCancelOutcome.stale);
      expect(counting.posts, 1, reason: 'sent once, never retried');
      expect(server.rides[id]!['status'], 'rider_onboard');
      expect(server.rides[id]!['cancellation'], isNull);
      expect(AppScope.instance.ride.status, RideStatus.driverWaiting);
      expect(await PendingCancelStore.all(), isEmpty);
      expect(rideJustChangedMessage, 'Your ride just changed, check it again.');
      // The refusal carried the trip as it is now.
      expect(
        AppScope.instance.ride.projectionVersionOf(id),
        server.rides[id]!['version'],
      );
    });

    test('a route change priced on an old version is refused as stale',
        () async {
      final seen = <_Seen>[];
      final session = RideSession()..observeProjectionVersion('rc1', 3);
      final controller = RouteChangeController(
        api: _scripted(seen, (request) => request.method == 'POST'
            ? _json(201, {'code': 'OK', 'newTotalMinor': 30000})
            : _json(409, {
                'code': 'version_mismatch',
                'message': 'stale',
                'retryable': false,
                'projection': {'tripId': 'rc1', 'status': 'arrived', 'version': 4},
              })),
        geocoding: _NoGeocoding(),
        session: session,
      );
      final ride = RideSnapshot(
        status: RideStatus.driverArriving,
        savedAt: DateTime.now(),
        pickupAddress: 'Pickup',
        destinationAddress: 'Destination',
        pickupLat: _pickup.lat,
        pickupLng: _pickup.lng,
        destinationLat: 59.40,
        destinationLng: 18.10,
        rideType: 'Movera',
        price: 319,
        paymentMethod: 'Cash',
        rideId: 'rc1',
      );
      final quote = await controller.preview(
        ride: ride,
        destinationAddress: 'Destination',
      );
      expect(seen.single.body['expectedVersion'], 3);
      session.observeProjectionVersion('rc1', 5);
      await expectLater(
        controller.apply(ride: ride, quote: quote),
        throwsA(isA<RouteChangeException>().having(
          (e) => e.message,
          'message',
          rideJustChangedMessage,
        )),
      );
      expect(seen.last.body['expectedVersion'], 3,
          reason: 'the version the price was asked for');
      expect(seen.where((r) => r.method == 'PATCH'), hasLength(1));
    });

    test('the demo transport reports the server version, not its own '
        'numbering', () async {
      final id = await book();
      final reported = <int>[];
      final events = <RideRealtimeEvent>[];
      final realtime = MockRideRealtime(
        api: api,
        assignAfter: const Duration(hours: 1),
        onProjectionVersion: (tripId, version) {
          if (tripId == id) reported.add(version);
        },
      );
      addTearDown(realtime.dispose);
      final sub = realtime.subscribe(id).listen(events.add);
      addTearDown(sub.cancel);
      realtime.assignNow();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reported, isNotEmpty);
      expect(reported.last, server.rides[id]!['version']);
      expect(events.last.version, isNot(reported.last));
    });

    test('the live transport reports the projection version', () async {
      final reported = <int>[];
      final realtime = ApiRideRealtime(
        api: ApiClient(
          client: MockClient((_) async => _json(200, {
            'tripId': 'live1',
            'status': 'accepted',
            'version': 4,
            'sequence': 17,
            'updatedAt': '2026-10-19T08:00:00Z',
          })),
        ),
        pollInterval: const Duration(hours: 1),
        onProjectionVersion: (_, version) => reported.add(version),
      );
      addTearDown(realtime.dispose);
      final sub = realtime.subscribe('live1').listen((_) {});
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(reported, [4]);
    });

    test('versions only grow and are kept per trip', () {
      final session = RideSession()
        ..observeProjectionVersion('a', 5)
        ..observeProjectionVersion('a', 3)
        ..observeProjection({'ride': {'tripId': 'b', 'version': 2}});
      expect(session.projectionVersionOf('a'), 5);
      expect(session.projectionVersionOf('b'), 2);
      session.reset();
      expect(session.projectionVersionOf('a'), isNull);
    });
  });

  group('R-O2: outbox replay after offline', () {
    test('re-read first; still cancellable at a newer version: sent with it',
        () async {
      final id = await book();
      final booked = server.rides[id]!['version'] as int;
      await PendingCancelStore.enqueue(rideId: id, expectedVersion: booked);
      final oldKey = (await PendingCancelStore.all()).single.idempotencyKey;
      // Meanwhile a driver accepted (the version moved on).
      await simulate(id, {'status': 'accepted'});

      final results = await FindingDriverController.flushPendingCancels(
        api: api,
      );
      expect(results[id], PendingCancelResult.sent);
      expect(server.rides[id]!['status'], 'cancelled_by_rider');
      expect(await PendingCancelStore.all(), isEmpty);
      expect(oldKey, isNotNull);
    });

    test('the request names the re-read version under a new key', () async {
      final seen = <_Seen>[];
      await PendingCancelStore.add(const PendingCancel(
        rideId: 'o1',
        idempotencyKey: 'old-key-0000000001',
        expectedVersion: 3,
      ));
      final results = await FindingDriverController.flushPendingCancels(
        api: _scripted(seen, (request) => request.method == 'GET'
            ? _json(200, {'tripId': 'o1', 'status': 'searching', 'version': 5})
            : _json(200, {
                'tripId': 'o1',
                'status': 'cancelled_by_rider',
                'version': 6,
              })),
      );
      expect(results['o1'], PendingCancelResult.sent);
      expect(seen.map((r) => '${r.method} ${r.path}'), [
        'GET /api/v1/rides/o1',
        'POST /api/v1/rides/o1/cancel',
      ]);
      expect(seen.last.body['expectedVersion'], 5);
      expect(seen.last.key, isNot('old-key-0000000001'));
    });

    test('an unchanged trip is replayed as queued (same key, same body)',
        () async {
      final seen = <_Seen>[];
      await PendingCancelStore.add(const PendingCancel(
        rideId: 'o2',
        idempotencyKey: 'same-key-000000001',
        expectedVersion: 5,
      ));
      await FindingDriverController.flushPendingCancels(
        api: _scripted(seen, (request) => request.method == 'GET'
            ? _json(200, {'tripId': 'o2', 'status': 'searching', 'version': 5})
            : _json(200, {'tripId': 'o2', 'status': 'cancelled_by_rider'})),
      );
      expect(seen.last.key, 'same-key-000000001');
      expect(seen.last.body['expectedVersion'], 5);
    });

    test('a queued cancel for a rider now on board is dropped and told',
        () async {
      final seen = <_Seen>[];
      await PendingCancelStore.add(const PendingCancel(
        rideId: 'o3',
        idempotencyKey: 'k-o3-000000000001',
        expectedVersion: 3,
      ));
      final reported = <({String rideId, bool stale})>[];
      final sub = ActiveRideController.queuedCancelNotices.listen(reported.add);
      addTearDown(sub.cancel);
      final results = await FindingDriverController.flushPendingCancels(
        api: _scripted(seen, (_) => _json(200, {
          'tripId': 'o3',
          'status': 'rider_onboard',
          'version': 9,
        })),
      );
      await Future<void>.delayed(Duration.zero);
      expect(results['o3'], PendingCancelResult.stale);
      expect(seen.map((r) => r.method), ['GET'], reason: 'nothing is sent');
      expect(reported.single, (rideId: 'o3', stale: true));
      expect(await PendingCancelStore.all(), isEmpty);
      // A screen that opens later (cold restore) still tells the rider.
      expect(ActiveRideController.takeQueuedCancelNotice('o3'), isTrue);
      expect(ActiveRideController.takeQueuedCancelNotice('o3'), isNull);
    });

    test('a queued end-early for a trip already over is not sent', () async {
      final seen = <_Seen>[];
      await PendingCancelStore.add(const PendingCancel(
        rideId: 'o4',
        idempotencyKey: 'k-o4-000000000001',
        command: PendingCancelCommand.endEarly,
      ));
      final results = await FindingDriverController.flushPendingCancels(
        api: _scripted(seen, (_) => _json(200, {
          'tripId': 'o4',
          'status': 'completed',
          'version': 12,
        })),
      );
      // rider-r4-24: the server closed it, so `ended` (was `gone`).
      expect(results['o4'], PendingCancelResult.ended);
      expect(seen.map((r) => r.method), ['GET']);
    });

    test('already cancelled by the rider: done, nothing sent (R-O3)',
        () async {
      final seen = <_Seen>[];
      await PendingCancelStore.add(const PendingCancel(
        rideId: 'o5',
        idempotencyKey: 'k-o5-000000000001',
      ));
      final results = await FindingDriverController.flushPendingCancels(
        api: _scripted(seen, (_) => _json(200, {
          'tripId': 'o5',
          'status': 'cancelled_by_rider',
          'version': 4,
        })),
      );
      expect(results['o5'], PendingCancelResult.sent);
      expect(seen.map((r) => r.method), ['GET']);
    });

    test('the re-read itself offline: the entry waits', () async {
      await PendingCancelStore.add(const PendingCancel(
        rideId: 'o6',
        idempotencyKey: 'k-o6-000000000001',
      ));
      final results = await FindingDriverController.flushPendingCancels(
        api: ApiClient(
          client: MockClient((_) async => throw http.ClientException('off')),
        ),
      );
      expect(results, isEmpty);
      expect((await PendingCancelStore.all()).single.rideId, 'o6');
    });
  });

  group('R-O1: the distance the app tracks on board', () {
    test('summed from the driver fixes after boarding only', () async {
      final feed = _Feed();
      addTearDown(feed.dispose);
      final tracking = DriverTrackingController(
        realtime: feed,
        pickupLat: _pickup.lat,
        pickupLng: _pickup.lng,
        persistRideSnapshot: false,
      );
      addTearDown(tracking.dispose);
      tracking.start(rideId: 'd1');
      var sequence = 0;
      Future<void> fix(RideStatus status, double lat) async {
        sequence += 1;
        feed.events.add(RideRealtimeEvent(
          tripId: 'd1',
          status: status,
          sequence: sequence,
          latitude: lat,
          longitude: _pickup.lng,
          locationAt: DateTime.now().add(Duration(seconds: sequence)),
        ));
        await Future<void>.delayed(Duration.zero);
      }

      await fix(RideStatus.driverArriving, 59.30);
      await fix(RideStatus.driverWaiting, _pickup.lat);
      expect(tracking.drivenMeters, 0);
      await fix(RideStatus.tripStarted, _pickup.lat);
      await fix(RideStatus.tripInProgress, _pickup.lat + 0.009);
      await fix(RideStatus.tripInProgress, _pickup.lat + 0.018);
      final expected = GeoDistance.metersBetween(
        _pickup.lat,
        _pickup.lng,
        _pickup.lat + 0.018,
        _pickup.lng,
      );
      expect(tracking.drivenMeters, closeTo(expected, 2));
    });
  });
}

/// Counts POSTs on their way to [inner].
class _CountingClient extends http.BaseClient {
  _CountingClient(this.inner);
  final http.Client inner;
  int posts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'POST') posts += 1;
    return inner.send(request);
  }
}

class _NoGeocoding implements GeocodingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
