// A whole ride of the rider's live (staging) wire against a running
// movera-server: real price, booking, the driver's steps followed through
// the realtime transport, rating, history, and a cancel. Skipped unless
// MOVERA_E2E_API names the server, e.g.
//
//   MOVERA_E2E_API=http://127.0.0.1:8131 flutter test test/e2e
//
// The server needs SEED_TEST_ON_START=true (test riders and drivers, code
// 1234). The driver side is driven through the API, as the driver app does.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/payments/data/api_payment_method_repository.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _base = Platform.environment['MOVERA_E2E_API'];
final _riderPhone =
    Platform.environment['MOVERA_E2E_RIDER'] ?? '+46701740609';
final _driverPhone =
    Platform.environment['MOVERA_E2E_DRIVER'] ?? '+46701740605';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test answers every real HTTP request with 400; this test talks
  // to a real server.
  HttpOverrides.global = null;

  const pickup = GeoPoint(59.3326, 18.0649);
  const dropoff = GeoPoint(59.3143, 18.0735);
  late ApiClient api;
  late _Driver driver;

  setUpAll(() async {
    if (_base == null) return;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final tokens = MemoryTokenStore();
    final session = await _signIn(_riderPhone, 'rider');
    await tokens.save(access: session.access, refresh: session.refresh);
    api = ApiClient(
      env: AppEnv(flavor: AppFlavor.staging, apiBaseUrl: _base!),
      client: http.Client(),
      tokens: tokens,
    );
    driver = _Driver((await _signIn(_driverPhone, 'driver')).access);
    await driver.online();
  });

  setUp(() async {
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..restoreFromBackend(RideStatus.idle);
    await RideSnapshotStore.clear();
  });

  Future<RideQuote> price(String category) => ApiQuoteRepository(api: api)
      .quote(
        rideType: category,
        distanceMeters: 2500,
        pickup: 'Sergels torg',
        destination: 'Medborgarplatsen',
        pickupPoint: pickup,
        destinationPoint: dropoff,
      );

  Future<String> book(RideQuote quote) => BookingCoordinator(api: api)
      .submitFinding(
        pickupAddress: 'Sergels torg',
        destinationAddress: 'Medborgarplatsen',
        pickupLat: pickup.latitude,
        pickupLng: pickup.longitude,
        destinationLat: dropoff.latitude,
        destinationLng: dropoff.longitude,
        rideType: quote.rideType,
        price: quote.totalMinor / 100,
        paymentMethod: 'cash',
        quoteId: quote.id,
        quoteExpiresAt: quote.expiresAt,
        quoteTotalMinor: quote.totalMinor,
        quoteCurrency: quote.currency,
      );

  test(
    'price, book, follow the driver to completed, rate, history',
    () async {
      final methods = await ApiPaymentMethodRepository(api: api).listMethods();
      expect(methods.map((m) => m.id), contains('cash'));
      final quote = await price('economy');
      _log('price: economy ${quote.totalMinor / 100} ${quote.currency} '
          '(${quote.id})');
      expect(quote.totalMinor, greaterThan(0));
      final tripId = await book(quote);
      _log('booked: $tripId, session ${AppScope.instance.ride.status.name}');
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);

      final realtime = ApiRideRealtime(
        api: api,
        pollInterval: const Duration(milliseconds: 500),
        onProjectionVersion: AppScope.instance.ride.observeProjectionVersion,
      );
      final seen = <RideStatus>[];
      final events = <RideRealtimeEvent>[];
      final subscription = realtime.subscribe(tripId).listen((event) {
        events.add(event);
        if (seen.isEmpty || seen.last != event.status) {
          seen.add(event.status);
          _log('rider sees ${event.status.name}'
              '${event.driver == null ? '' : ' (driver ${event.driver!.firstName}, '
                  '${event.driver!.vehicleLabel}, ${event.driver!.plate})'}');
        }
      });

      var trip = await driver.accept(tripId);
      final active = await ApiActiveTripRepository(api: api).fetchActive();
      expect(active?.rideId, tripId);
      _log('active trip read back: ${active?.status.name}, '
          'driver ${active?.driver?.firstName}');
      for (final step in ['head-to-pickup', 'arrive', 'board', 'start']) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        trip = await driver.step(trip, step);
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      trip = await driver.complete(trip, quote);
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      await subscription.cancel();
      realtime.dispose();

      expect(seen.first, RideStatus.findingDriver);
      expect(
        seen,
        containsAllInOrder([
          RideStatus.driverAssigned,
          RideStatus.driverArriving,
          RideStatus.driverWaiting,
          RideStatus.tripStarted,
          RideStatus.tripInProgress,
          RideStatus.ratingPending,
        ]),
      );
      final assigned = events.firstWhere(
        (e) => e.status == RideStatus.driverAssigned,
      );
      expect(assigned.driver?.firstName, isNotEmpty);
      expect(assigned.driver?.plate, isNotNull);
      expect(await ApiActiveTripRepository(api: api).fetchActive(), isNull);

      await RideFeedbackRepository(api: api).submit(
        rideId: tripId,
        rating: 5,
        idempotencyKey: 'e2e-rating-${DateTime.now().microsecondsSinceEpoch}',
      );
      final rated = await api.get(api.tripPath(tripId));
      expect(rated['ratingStatus'], 'submitted');
      _log('rated 5 stars → ratingStatus ${rated['ratingStatus']}');

      final history = await ApiRideHistoryRepository(api: api).loadOnDemand();
      expect(history.map((r) => r.reservationId), contains('ondemand-$tripId'));
      _log('history has ${history.length} trip(s), this one included');
    },
    skip: _base == null ? 'MOVERA_E2E_API is not set' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'cancel while searching, and after the driver accepted',
    () async {
      final first = await book(await price('economy'));
      AppScope.instance.ride.rideId = null;
      await BookingCoordinator(api: api).cancel(
        rideId: first,
        key: 'e2e-cancel-${DateTime.now().microsecondsSinceEpoch}',
      );
      final cancelled = await api.get(api.tripPath(first));
      expect(cancelled['status'], 'cancelled_by_rider');
      _log('cancel while searching → ${cancelled['status']}, fee '
          '${(cancelled['cancellation'] as Map)['fee']}');

      await RideSnapshotStore.clear();
      final second = await book(await price('economy'));
      await driver.accept(second);
      final accepted = await api.get(api.tripPath(second));
      AppScope.instance.ride.observeProjection(accepted);
      await BookingCoordinator(api: api).cancel(
        rideId: second,
        key: 'e2e-cancel-${DateTime.now().microsecondsSinceEpoch}',
      );
      final after = await api.get(api.tripPath(second));
      expect(after['status'], 'cancelled_by_rider');
      _log('cancel after accept → ${after['status']}, fee '
          '${(after['cancellation'] as Map)['fee']}');
    },
    skip: _base == null ? 'MOVERA_E2E_API is not set' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'end the trip early once on board',
    () async {
      await RideSnapshotStore.clear();
      final tripId = await book(await price('economy'));
      var trip = await driver.accept(tripId);
      for (final step in ['head-to-pickup', 'arrive', 'board', 'start']) {
        trip = await driver.step(trip, step);
      }
      final current = await api.get(api.tripPath(tripId));
      final entry = PendingCancel(
        rideId: tripId,
        reasonId: 'plans_changed',
        idempotencyKey: 'e2e-end-${DateTime.now().microsecondsSinceEpoch}',
        command: PendingCancelCommand.endEarly,
        expectedVersion: current['version'] as int,
      );
      final ended = await api.post(
        api.tripPath(tripId, entry.command.pathSegment),
        body: entry.body(),
        idempotencyKey: entry.idempotencyKey,
      );
      expect(ended['status'], 'cancelled_by_rider');
      expect(ended['ratingStatus'], 'pending');
      _log('end early → ${ended['status']}, charged ${ended['fare']}');
    },
    skip: _base == null ? 'MOVERA_E2E_API is not set' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

void _log(String line) {
  // ignore: avoid_print
  print('E2E $line');
}

int _keys = 0;

Future<Map<String, dynamic>> _call(
  String method,
  String path, {
  String? token,
  Object? body,
}) async {
  final request = http.Request(method, Uri.parse('$_base/api/v1$path'))
    ..headers.addAll({
      'content-type': 'application/json',
      'x-api-version': '0.5',
      'authorization': ?(token == null ? null : 'Bearer $token'),
      if (method != 'GET')
        'idempotency-key':
            'e2e-driver-${DateTime.now().microsecondsSinceEpoch}-${++_keys}',
    });
  if (body != null) request.body = jsonEncode(body);
  final response = await http.Response.fromStream(await request.send());
  if (response.statusCode >= 400) {
    throw StateError('$method $path → ${response.statusCode} ${response.body}');
  }
  if (response.body.isEmpty) return const {};
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<({String access, String refresh})> _signIn(
  String phone,
  String app,
) async {
  final otp = await _call(
    'POST',
    '/auth/otp/request',
    body: {'phone': phone, 'app': app},
  );
  final session = await _call(
    'POST',
    '/auth/otp/verify',
    body: {'phone': phone, 'sessionId': otp['sessionId'], 'code': '1234'},
  );
  return (
    access: session['accessToken'] as String,
    refresh: session['refreshToken'] as String,
  );
}

/// The driver app's side of a ride, through the API.
class _Driver {
  _Driver(this.token);

  final String token;
  static const _near = (lat: 59.333, lng: 18.06);
  static const _pickup = (lat: 59.3326, lng: 18.0649);
  static const _dropoff = (lat: 59.3143, lng: 18.0735);

  Map<String, Object> _fix(({double lat, double lng}) at) => {
    'lat': at.lat,
    'lng': at.lng,
    'accuracy': 8,
    'measuredAt': DateTime.now().toUtc().toIso8601String(),
  };

  Future<void> online() async {
    final me = await _call('GET', '/driver/profile', token: token);
    await _call(
      'POST',
      '/driver/location',
      token: token,
      body: {
        'fixes': [_fix(_near)],
      },
    );
    if (me['onlineStatus'] != 'online') {
      await _call(
        'POST',
        '/driver/availability',
        token: token,
        body: {
          'expectedVersion': me['version'],
          'onlineStatus': 'online',
          'location': _fix(_near),
        },
      );
    }
  }

  Future<Map<String, dynamic>> accept(String tripId) async {
    for (var i = 0; i < 40; i++) {
      await _call(
        'POST',
        '/driver/location',
        token: token,
        body: {
          'fixes': [_fix(_near)],
        },
      );
      final feed = await _call('GET', '/driver/offers', token: token);
      final items = (feed['items'] ?? feed['offers']) as List? ?? const [];
      for (final offer in items.cast<Map<String, dynamic>>()) {
        if (offer['tripId'] == tripId) {
          final accepted = await _call(
            'POST',
            '/offers/${offer['offerId']}/accept',
            token: token,
            body: {'expectedVersion': offer['version']},
          );
          _log('driver accepted offer ${offer['offerId']}');
          return (accepted['trip'] as Map<String, dynamic>?) ?? accepted;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw StateError('no offer for $tripId reached the driver');
  }

  Future<Map<String, dynamic>> step(
    Map<String, dynamic> trip,
    String step,
  ) async {
    final next = await _call(
      'POST',
      '/trips/${trip['tripId']}/$step',
      token: token,
      body: {
        'expectedVersion': trip['version'],
        'location': _fix(step == 'head-to-pickup' ? _near : _pickup),
      },
    );
    _log('driver $step → ${next['status']}');
    return next;
  }

  Future<Map<String, dynamic>> complete(
    Map<String, dynamic> trip,
    RideQuote quote,
  ) async {
    final done = await _call(
      'POST',
      '/trips/${trip['tripId']}/complete',
      token: token,
      body: {
        'expectedVersion': trip['version'],
        'location': _fix(_dropoff),
        'cashCollected': trip['fare'] ??
            {'amountMinor': quote.totalMinor, 'currency': quote.currency},
      },
    );
    _log('driver complete → ${done['status']}');
    return done;
  }
}
