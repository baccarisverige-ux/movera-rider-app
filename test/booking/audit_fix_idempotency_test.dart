import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what reaches the in-process backend. [timeOutNextBooking] makes
/// the next POST /rides reach the server (which creates the ride) and then
/// time out on the client, like a slow network.
class _Backend extends http.BaseClient {
  _Backend(this.inner);

  final InProcessMockClient inner;
  final List<String?> bookingKeys = [];
  final List<Map<String, dynamic>> bookingBodies = [];
  final List<Map<String, dynamic>> quoteBodies = [];
  bool timeOutNextBooking = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final body = request is http.Request && request.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(request.body) as Map)
        : <String, dynamic>{};
    if (request.method == 'POST' && path == '/api/v1/quotes') {
      quoteBodies.add(body);
    }
    if (request.method == 'POST' && path == '/api/v1/rides') {
      bookingKeys.add(request.headers['Idempotency-Key']);
      bookingBodies.add(body);
      if (timeOutNextBooking) {
        timeOutNextBooking = false;
        final response = await inner.send(request);
        await response.stream.drain<void>();
        throw TimeoutException('client gave up');
      }
    }
    return inner.send(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });

  tearDown(() {
    FindingDriverController.active = null;
    AppScope.instance.ride.restoreFromBackend(RideStatus.idle);
    AppScope.instance.ride.rideId = null;
  });

  const pickup = GeoPoint(59.3326, 18.0649);
  const drop = GeoPoint(59.3426, 18.0498);

  Future<RideQuote> freshQuote(ApiClient api, {GeoPoint from = pickup}) =>
      ApiQuoteRepository(api: api).quote(
        rideType: 'economy',
        distanceMeters: 1500,
        pickupPoint: from,
        destinationPoint: drop,
      );

  Future<String> book(
    BookingCoordinator booking,
    RideQuote quote, {
    GeoPoint from = pickup,
    String paymentMethod = 'visa',
    GeoPoint to = drop,
  }) => booking.submitFinding(
    pickupAddress: 'Sergels torg 1',
    destinationAddress: 'Odenplan 2',
    pickupLat: from.latitude,
    pickupLng: from.longitude,
    destinationLat: to.latitude,
    destinationLng: to.longitude,
    rideType: 'economy',
    price: quote.totalMinor / 100,
    paymentMethod: paymentMethod,
    quoteId: quote.id,
    quoteSignedPayload: quote.signedPayload,
    quoteExpiresAt: quote.expiresAt,
    quoteTotalMinor: quote.totalMinor,
    rideTypeLabel: 'Movera',
    paymentMethodLabel: 'Visa •••• 4242',
  );

  group('RIDE-3: one idempotency key per booking intent', () {
    test(
      'a retry after a timeout reuses the key although the quote was '
      'refreshed and the pin moved a step; the server keeps one ride',
      () async {
        final mock = InProcessMockClient();
        final backend = _Backend(mock)..timeOutNextBooking = true;
        final api = ApiClient(client: backend);
        final booking = BookingCoordinator(api: api);

        final first = await freshQuote(api);
        await expectLater(book(booking, first), throwsA(isA<ApiError>()));
        expect(mock.rides, hasLength(1), reason: 'the server did create it');

        // SelectRide refreshes the quotes after the failure; Set pickup
        // confirms a pin a couple of metres away.
        const nudged = GeoPoint(59.33261, 18.06491);
        final second = await freshQuote(api, from: nudged);
        expect(second.id, isNot(first.id));
        final rideId = await book(booking, second, from: nudged);

        expect(backend.bookingKeys, hasLength(2));
        expect(backend.bookingKeys[1], backend.bookingKeys[0]);
        expect(mock.rides, hasLength(1), reason: 'no second ride');
        expect(rideId, mock.rides.keys.single);
      },
    );

    test(
      'a refused booking (4xx) is not a ride: the next try gets a new key',
      () async {
        final mock = InProcessMockClient();
        final backend = _Backend(mock);
        final api = ApiClient(client: backend);
        final booking = BookingCoordinator(api: api);

        final quote = await freshQuote(api);
        // The server forgets the quote: 409 QUOTE_NOT_FOUND.
        mock.quotes.clear();
        await expectLater(book(booking, quote), throwsA(isA<ApiError>()));
        await book(booking, await freshQuote(api));

        expect(backend.bookingKeys, hasLength(2));
        expect(backend.bookingKeys[1], isNot(backend.bookingKeys[0]));
      },
    );

    test('a different trip, or the same trip after a booking succeeded '
        '("Try again"), gets a new key', () async {
      final mock = InProcessMockClient();
      final backend = _Backend(mock)..timeOutNextBooking = true;
      final api = ApiClient(client: backend);
      final booking = BookingCoordinator(api: api);

      await expectLater(
        book(booking, await freshQuote(api)),
        throwsA(isA<ApiError>()),
      );
      // Another payment method is another booking.
      await book(booking, await freshQuote(api), paymentMethod: 'apple');
      FindingDriverController.active = null;
      // The same trip again once that one went through.
      await book(booking, await freshQuote(api), paymentMethod: 'apple');

      expect(backend.bookingKeys.toSet(), hasLength(3));
    });
  });

  group('ARCH-8: quotes carry the points the server prices', () {
    test('ApiQuoteRepository sends pickup, destination and stops as '
        'coordinates; the distance stays only as a hint', () async {
      final mock = InProcessMockClient();
      final backend = _Backend(mock);
      final api = ApiClient(client: backend);

      await ApiQuoteRepository(api: api).quote(
        rideType: 'economy',
        distanceMeters: 1234,
        pickup: 'Sergels torg 1',
        destination: 'Odenplan 2',
        pickupPoint: pickup,
        destinationPoint: drop,
        stops: const [
          RouteStop(address: 'Hötorget', latitude: 59.3365, longitude: 18.0586),
        ],
      );

      final body = backend.quoteBodies.single;
      expect(body['pickupLat'], pickup.latitude);
      expect(body['pickupLng'], pickup.longitude);
      expect(body['destinationLat'], drop.latitude);
      expect(body['destinationLng'], drop.longitude);
      expect(body['stops'], [
        {'address': 'Hötorget', 'lat': 59.3365, 'lng': 18.0586},
      ]);
      // Old fields kept until the backend contract is agreed.
      expect(body['distanceMeters'], 1234);
      expect(body['pickup'], 'Sergels torg 1');
    });

    test(
      'the mock prices from the points, not from the client distance',
      () async {
        final api = ApiClient(client: InProcessMockClient());
        final repo = ApiQuoteRepository(api: api);
        final honest = await repo.quote(
          rideType: 'economy',
          distanceMeters: 30000,
          pickupPoint: pickup,
          destinationPoint: drop,
        );
        final lying = await repo.quote(
          rideType: 'economy',
          distanceMeters: 1,
          pickupPoint: pickup,
          destinationPoint: drop,
        );
        expect(lying.totalMinor, honest.totalMinor);
      },
    );

    test('a booking that fetches its own quote sends the points', () async {
      final mock = InProcessMockClient();
      final backend = _Backend(mock);
      final booking = BookingCoordinator(api: ApiClient(client: backend));

      await booking.submitFinding(
        pickupAddress: 'Sergels torg 1',
        destinationAddress: 'Odenplan 2',
        pickupLat: pickup.latitude,
        pickupLng: pickup.longitude,
        destinationLat: drop.latitude,
        destinationLng: drop.longitude,
        rideType: 'economy',
        price: 0,
        paymentMethod: 'visa',
      );

      final body = backend.quoteBodies.single;
      expect(body['pickupLat'], pickup.latitude);
      expect(body['destinationLng'], drop.longitude);
    });
  });

  test('ARCH-20: the booking keeps the offer ceiling the server set, for '
      'Finding and for a reload', () async {
    final mock = InProcessMockClient();
    final api = ApiClient(client: mock);
    final booking = BookingCoordinator(api: api);
    final quote = await freshQuote(api);
    final rideId = await book(booking, quote);

    final serverMax = mock.rides[rideId]!['maxOfferMinor'] as int;
    expect(serverMax, ((quote.totalMinor / 100 * 1.8).round()) * 100);
    expect(AppScope.instance.ride.bookedMaxOfferMinor, serverMax);
    expect((await RideSnapshotStore.read())?.maxOfferMinor, serverMax);
  });

  group('RIDE-22: scheduled bookings carry the route and the quote', () {
    test('the body has the route and quote; two rides at the same time with '
        'other destinations get different keys', () async {
      final mock = InProcessMockClient();
      final backend = _Backend(mock)..timeOutNextBooking = true;
      final api = ApiClient(client: backend);
      final booking = BookingCoordinator(api: api);
      final quote = await freshQuote(api);

      Future<String> schedule(String destination, double lat) =>
          booking.requestBooking(
            rideType: 'economy',
            paymentMethod: 'visa',
            scheduledAt: '2026-10-20T08:00:00Z',
            pickupAddress: 'Sergels torg 1',
            pickupLat: pickup.latitude,
            pickupLng: pickup.longitude,
            destinationAddress: destination,
            destinationLat: lat,
            destinationLng: drop.longitude,
            quoteId: quote.id,
            quoteSignedPayload: quote.signedPayload,
            quoteExpiresAt: quote.expiresAt,
            quoteTotalMinor: quote.totalMinor,
          );

      await expectLater(
        schedule('Odenplan 2', drop.latitude),
        throwsA(isA<ApiError>()),
      );
      await schedule('Arlanda Airport', 59.65);

      expect(backend.bookingKeys, hasLength(2));
      expect(backend.bookingKeys[1], isNot(backend.bookingKeys[0]));
      final body = backend.bookingBodies.last;
      expect(body['pickupLat'], pickup.latitude);
      expect(body['destinationAddress'], 'Arlanda Airport');
      expect(body['destinationLat'], 59.65);
      expect(body['quoteId'], quote.id);
      expect(body['quoteTotalMinor'], quote.totalMinor);
      expect(body['categoryId'], 'economy');
    });

    test(
      'the mock holds a scheduled booking to the quote it carries',
      () async {
        final mock = InProcessMockClient();
        final api = ApiClient(client: mock);
        final booking = BookingCoordinator(api: api);
        final quote = await freshQuote(api);

        await expectLater(
          booking.requestBooking(
            rideType: 'economy',
            paymentMethod: 'visa',
            scheduledAt: '2026-10-20T08:00:00Z',
            pickupAddress: 'Sergels torg 1',
            destinationAddress: 'Odenplan 2',
            quoteId: quote.id,
            quoteSignedPayload: quote.signedPayload,
            quoteExpiresAt: quote.expiresAt,
            quoteTotalMinor: quote.totalMinor + 100,
          ),
          throwsA(
            isA<ApiError>().having(
              (e) => e.code,
              'code',
              'QUOTE_AMOUNT_MISMATCH',
            ),
          ),
        );
      },
    );
  });
}
