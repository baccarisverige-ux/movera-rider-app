import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mock_fare.dart';

class _Geo implements GeocodingRepository {
  _Geo([this.known = const {}]);
  final Map<String, GeoPoint> known;

  @override
  Future<PlaceResult?> forward(String query) async {
    final point = known[query];
    return point == null ? null : PlaceResult(address: query, point: point);
  }

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

/// Answers every request with [handler] and records the headers and bodies.
class _Recorder extends http.BaseClient {
  _Recorder(this.handler);
  final http.Response Function(http.BaseRequest) handler;
  final keys = <String?>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    keys.add(request.headers['Idempotency-Key']);
    final r = handler(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(r.body)),
      r.statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// In front of the in-process backend: records route-change PATCHes and can
/// let the next one reach the server and then time out on the client.
class _Backend extends http.BaseClient {
  _Backend(this.inner);
  final InProcessMockClient inner;
  final keys = <String?>[];
  final bodies = <Map<String, dynamic>>[];
  bool timeOutNextPatch = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'PATCH') {
      keys.add(request.headers['Idempotency-Key']);
      bodies.add(
        Map<String, dynamic>.from(
          jsonDecode((request as http.Request).body) as Map,
        ),
      );
      if (timeOutNextPatch) {
        timeOutNextPatch = false;
        final response = await inner.send(request);
        await response.stream.drain<void>();
        throw TimeoutException('client gave up');
      }
    }
    return inner.send(request);
  }
}

const _env = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://x.invalid',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  const pickup = GeoPoint(59.3326, 18.0649);
  const drop = GeoPoint(59.3426, 18.0498);
  const farAway = GeoPoint(59.4000, 18.2000);

  RideSnapshot ride({
    String paymentMethod = 'Visa •••• 4242',
    String? paymentMethodId = 'visa',
  }) => RideSnapshot(
    status: RideStatus.driverArriving,
    savedAt: DateTime.now(),
    pickupAddress: 'Sergels torg 1',
    destinationAddress: 'Odenplan 2',
    pickupLat: pickup.latitude,
    pickupLng: pickup.longitude,
    destinationLat: drop.latitude,
    destinationLng: drop.longitude,
    rideType: 'Movera',
    price: 200,
    paymentMethod: paymentMethod,
    paymentMethodId: paymentMethodId,
    categoryId: 'economy',
    rideId: 'ride-route-1',
  );

  InProcessMockClient server() {
    final mock = InProcessMockClient();
    mock.rides['ride-route-1'] = {
      'id': 'ride-route-1',
      'status': 'driverArriving',
      'pickupAddress': 'Sergels torg 1',
      'pickupLat': pickup.latitude,
      'pickupLng': pickup.longitude,
      'destinationAddress': 'Odenplan 2',
      'destinationLat': drop.latitude,
      'destinationLng': drop.longitude,
      'price': 200.0,
      'bookedPrice': 200.0,
      'bookedKm': 1.4,
      'stops': <Map<String, dynamic>>[],
      'version': 3,
    };
    return mock;
  }

  RouteChangeController changes(http.Client client) => RouteChangeController(
    api: ApiClient(client: client),
    geocoding: _Geo({
      'Arlanda': farAway,
      'Kista': const GeoPoint(59.40, 17.94),
    }),
  );

  group('ARCH-4: one key per confirmed route change', () {
    // The audit repro (arch_repro_test.dart test 2), inverted.
    test('the same change sent twice gets the same Idempotency-Key', () async {
      final rec = _Recorder(
        (_) =>
            http.Response(jsonEncode({'code': 'OK', 'newPriceKr': 300}), 200),
      );
      final api = ApiClient(client: rec, env: _env, tokens: MemoryTokenStore());
      final c = RouteChangeController(api: api, geocoding: _Geo());
      final snapshot = RideSnapshot(
        status: RideStatus.driverArriving,
        savedAt: DateTime.now(),
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.1,
        pickupLng: 18.0,
        destinationLat: 59.2,
        destinationLng: 18.1,
        rideType: 'economy',
        price: 259,
        paymentMethod: 'Visa •••• 4242',
        rideId: 'ride_1',
      );
      const quote = RouteChangeQuote(
        pickupAddress: 'A',
        pickupPoint: GeoPoint(59.1, 18.0),
        destinationAddress: 'C',
        destinationPoint: GeoPoint(59.3, 18.2),
        stops: [],
        oldPriceKr: 259,
        newPriceKr: 300,
      );
      await c.apply(ride: snapshot, quote: quote);
      await c.apply(ride: snapshot, quote: quote);
      expect(rec.keys.length, 2);
      expect(rec.keys[0], isNotNull);
      expect(rec.keys[1], rec.keys[0]);
    });

    test('a resend after a timeout reuses the key, the change is adopted '
        'and the difference is charged once', () async {
      final mock = server();
      final backend = _Backend(mock)..timeOutNextPatch = true;
      final first = changes(backend);
      final quote = await first.preview(
        ride: ride(),
        destinationAddress: 'Arlanda',
      );
      // rider-u38: the lost answer is asked for again with the same key, so
      // the change the server applied is not reported as failed.
      final updated = await first.apply(ride: ride(), quote: quote);
      expect(updated.destinationAddress, 'Arlanda');

      expect(backend.keys, hasLength(2));
      expect(backend.keys[1], backend.keys[0]);
      final adjustments =
          mock.rides['ride-route-1']!['paymentAdjustments'] as List;
      expect(adjustments, hasLength(1));
    });

    test('a different change gets a different key', () async {
      final backend = _Backend(server());
      final c = changes(backend);
      final arlanda = await c.preview(
        ride: ride(),
        destinationAddress: 'Arlanda',
      );
      final kista = await c.preview(ride: ride(), destinationAddress: 'Kista');
      await c.apply(ride: ride(), quote: arlanda);
      await c.apply(ride: ride(), quote: kista);
      expect(backend.keys[1], isNot(backend.keys[0]));
    });
  });

  group('ARCH-14: apply is bound to the price the rider confirmed', () {
    test('apply sends the route quote id and the confirmed amount', () async {
      final backend = _Backend(server());
      final c = changes(backend);
      final quote = await c.preview(
        ride: ride(),
        destinationAddress: 'Arlanda',
      );
      expect(quote.routeQuoteId, isNotNull);
      expect(quote.newTotalMinor, (quote.newPriceKr * 100).round());

      await c.apply(ride: ride(), quote: quote);
      final body = backend.bodies.single;
      expect(body['routeQuoteId'], quote.routeQuoteId);
      expect(body['expectedTotalMinor'], quote.newTotalMinor);
      expect(body['expectedDifferenceMinor'], quote.differenceMinor);
    });

    test('when the price changed after the preview the server refuses and '
        'nothing is charged; the rider is asked to look again', () async {
      final mock = server();
      final c = changes(_Backend(mock));
      final quote = await c.preview(
        ride: ride(),
        destinationAddress: 'Arlanda',
      );
      // The server's pricing moves before the rider confirms.
      mock.rides['ride-route-1']!['bookedPrice'] = 260.0;

      await expectLater(
        c.apply(ride: ride(), quote: quote),
        throwsA(
          isA<RouteChangeException>().having(
            (e) => e.failure,
            'failure',
            RouteChangeFailure.priceChanged,
          ),
        ),
      );
      final stored = mock.rides['ride-route-1']!;
      expect(stored['destinationAddress'], 'Odenplan 2');
      expect(stored['paymentAdjustments'], isNull);
    });
  });

  group('ARCH-9: the payment method travels and is stored by id', () {
    test('the route-change PATCH sends the method id; the server charges by '
        'id, whatever the label says', () async {
      final mock = server();
      final backend = _Backend(mock);
      final c = changes(backend);
      final quote = await c.preview(
        ride: ride(),
        destinationAddress: 'Arlanda',
      );
      // A label that reads like cash must not stop a card from being charged.
      await c.apply(
        ride: ride(paymentMethod: 'Card, pay in car'),
        quote: quote,
      );

      expect(backend.bodies.single['paymentMethodId'], 'visa');
      final adjustment =
          (mock.rides['ride-route-1']!['paymentAdjustments'] as List).single
              as Map;
      expect(adjustment['method'], 'visa');
      expect(adjustment['status'], 'captured');
    });

    test('cash by id: nothing is charged now', () async {
      final mock = server();
      final c = changes(_Backend(mock));
      final quote = await c.preview(
        ride: ride(),
        destinationAddress: 'Arlanda',
      );
      await c.apply(
        ride: ride(paymentMethod: 'Betala i bilen', paymentMethodId: 'cash'),
        quote: quote,
      );
      expect(mock.rides['ride-route-1']!['paymentAdjustments'], isNull);
    });

    test(
      'a wallet ride is charged by its id, even after a label rename',
      () async {
        final wallet = WalletController();
        final completed = ride(
          paymentMethod: 'Balance',
          paymentMethodId: 'wallet',
        ).copyWith(status: RideStatus.tripCompleted, price: 100);
        expect(
          await wallet.chargeCompletedRide(completed, rideId: 'ride-route-1'),
          isNotNull,
        );
        final card = ride(
          paymentMethod: 'Wallet-friendly Visa',
          paymentMethodId: 'visa',
        ).copyWith(status: RideStatus.tripCompleted, rideId: 'ride-route-2');
        expect(
          await wallet.chargeCompletedRide(card, rideId: 'ride-route-2'),
          isNull,
        );
      },
    );
  });

  group('ARCH-20: the offer ceiling does not move with a raised offer', () {
    FindingDriverController finding(InProcessMockClient mock, RideSnapshot s) {
      final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
      addTearDown(rt.dispose);
      final controller = FindingDriverController(
        realtime: rt,
        ride: RideSession()..rideId = s.rideId,
        store: FindingDriverRepository(),
        api: ApiClient(client: mock),
        delayedAfter: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.start(snapshot: s, onTick: (_) {}, onMatched: () {});
      return controller;
    }

    test('after a bump and a reload the ceiling is still the booked one, and '
        'the server refuses an offer above it', () async {
      final mock = InProcessMockClient();
      final booked = RideSnapshot(
        status: RideStatus.findingDriver,
        savedAt: DateTime.now(),
        pickupAddress: 'A',
        destinationAddress: 'B',
        pickupLat: 59.3,
        pickupLng: 18.0,
        destinationLat: 59.4,
        destinationLng: 18.1,
        rideType: 'Movera',
        price: 200,
        paymentMethod: 'Visa',
        rideId: 'ride-bump',
        maxOfferMinor: 36000,
      );
      mock.rides['ride-bump'] = {
        'id': 'ride-bump',
        'status': 'findingDriver',
        'price': 200,
        'maxOfferMinor': 36000,
      };

      final first = finding(mock, booked);
      expect(first.maxOfferPrice, 360);
      expect(await first.confirmPriceIncrease(100), isTrue);
      expect(first.currentPrice, 300);
      first.dispose();

      // Reload: the saved snapshot comes back with the bumped fare.
      final saved = await RideSnapshotStore.read();
      expect(saved?.price, 300);
      expect(saved?.maxOfferMinor, 36000);
      final restored = finding(mock, saved!);
      expect(restored.maxOfferPrice, 360, reason: 'not 1.8 × 300');
      expect(await restored.confirmPriceIncrease(100), isFalse);

      // The server holds the ceiling on its own too.
      final api = ApiClient(client: mock);
      await expectLater(
        api.patch('/api/v1/rides/ride-bump', body: {'offerIncreaseKr': 100}),
        throwsA(anything),
      );
      expect(mockFareKr(mock.rides['ride-bump']!), 300);
    });
  });
}
