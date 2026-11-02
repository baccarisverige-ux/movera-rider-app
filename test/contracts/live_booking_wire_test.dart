import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/ride_status.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/payments/data/api_payment_method_repository.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The live (staging/production) booking wire against movera-server's
/// contract shapes (openapi v0.5). The fixtures are answers a local
/// movera-server gave (trimmed), so the rider reads what the server sends.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.test',
  );

  final pickup = const GeoPoint(59.3326, 18.0649);
  final dropoff = const GeoPoint(59.3143, 18.0735);
  final soon = DateTime.now().toUtc().add(const Duration(minutes: 5));

  Map<String, dynamic> quote(String id, String category, int minor) => {
    'quoteId': id,
    'categoryId': category,
    'total': {'amountMinor': minor, 'currency': 'SEK'},
    'fareLines': [
      {
        'code': 'base',
        'amount': {'currency': 'SEK', 'amountMinor': 2900},
      },
      {
        'code': 'distance',
        'amount': {'currency': 'SEK', 'amountMinor': 3139},
      },
      {
        'code': 'app_fee',
        'amount': {'currency': 'SEK', 'amountMinor': 865},
      },
      {
        'code': 'discount',
        'amount': {'currency': 'SEK', 'amountMinor': -500},
      },
    ],
    'expiresAt': soon.toIso8601String(),
    'pickup': {'lat': 59.3326, 'lng': 18.0649, 'address': 'Sergels torg'},
    'dropoff': {'lat': 59.3143, 'lng': 18.0735, 'address': 'Medborgarplatsen'},
    'stops': <Object>[],
    'surgeMultiplier': 1,
  };

  Map<String, dynamic> trip({
    String status = 'searching',
    int version = 3,
    Map<String, dynamic>? driver,
    String? paymentStatus,
    String ratingStatus = 'not_requested',
    Map<String, dynamic>? cancellation,
  }) => {
    'tripId': 'trp_1',
    'rideId': 'trp_1',
    'status': status,
    'version': version,
    'sequence': version - 1,
    'kind': 'live',
    'createdAt': '2026-10-26T01:00:23.518Z',
    'updatedAt': '2026-10-26T01:00:23.518Z',
    'acceptedAt': null,
    'riderId': 'rdr_1',
    'zoneId': 'Z001',
    'categoryId': 'economy',
    'pickup': {'lat': 59.3326, 'lng': 18.0649, 'address': 'Sergels torg'},
    'dropoff': {'lat': 59.3143, 'lng': 18.0735, 'address': 'Medborgarplatsen'},
    'stops': <Object>[],
    'fare': {'amountMinor': 9500, 'currency': 'SEK'},
    'fareLines': <Object>[],
    'paymentMethod': 'cash',
    'paymentStatus': ?paymentStatus,
    'ratingStatus': ratingStatus,
    'pinRequired': false,
    'driver': ?driver,
    'cancellation': ?cancellation,
    'quote': {
      'quoteId': 'qte_economy',
      'total': {'amountMinor': 9500, 'currency': 'SEK'},
      'expiresAt': soon.toIso8601String(),
    },
  };

  const driver = {
    'vehicle': {
      'make': 'Volvo',
      'color': 'Black',
      'model': 'V60',
      'plate': 'TST 001',
      'vehicleId': 'veh_1',
      'categoryId': 'economy',
    },
    'driverId': 'drv_1',
    'firstName': 'Test',
  };

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..restoreFromBackend(RideStatus.idle);
    await RideSnapshotStore.clear();
  });

  group('quotes', () {
    test('POST /quotes sends a QuoteRequest and reads the QuoteList', () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        env: staging,
        client: MockClient((request) async {
          requests.add(request);
          return json({
            'quotes': [
              quote('qte_economy', 'economy', 9500),
              quote('qte_comfort', 'comfort', 11900),
            ],
            'zoneId': 'Z001',
            'serverTime': DateTime.now().toUtc().toIso8601String(),
          }, 201);
        }),
      );
      final repository = ApiQuoteRepository(api: api);

      final economy = await repository.quote(
        rideType: 'economy',
        distanceMeters: 2500,
        pickup: 'Sergels torg',
        destination: 'Medborgarplatsen',
        pickupPoint: pickup,
        destinationPoint: dropoff,
      );
      final comfort = await repository.quote(
        rideType: 'comfort',
        distanceMeters: 2500,
        pickup: 'Sergels torg',
        destination: 'Medborgarplatsen',
        pickupPoint: pickup,
        destinationPoint: dropoff,
      );

      // One request prices every category of the zone.
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.url.path, '/api/v1/quotes');
      expect(request.headers['Idempotency-Key'], isNotNull);
      expect(
        request.headers['Idempotency-Key']!.length,
        greaterThanOrEqualTo(16),
      );
      expect(request.headers['X-Api-Version'], '0.5');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {
        'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
        'dropoff': {
          'address': 'Medborgarplatsen',
          'lat': 59.3143,
          'lng': 18.0735,
        },
        'stops': <Object>[],
      });

      expect(economy.id, 'qte_economy');
      expect(economy.rideType, 'economy');
      expect(economy.totalMinor, 9500);
      expect(economy.currency, 'SEK');
      expect(economy.serverHeld, isTrue);
      expect(economy.signedPayload, isNull);
      expect(economy.bookable, isTrue);
      expect(economy.discountMinor, 500);
      expect(economy.bookingFeeMinor, 865);
      expect(comfort.id, 'qte_comfort');
      expect(comfort.totalMinor, 11900);
      // CreateTrip must name exactly what was priced.
      expect(ApiQuoteRepository.routeOf('qte_economy')?.pickup, {
        'lat': 59.3326,
        'lng': 18.0649,
        'address': 'Sergels torg',
      });
    });

    test('a category the zone does not offer is reported as such', () async {
      final api = ApiClient(
        env: staging,
        client: MockClient(
          (_) async => json({
            'quotes': [quote('qte_e2', 'economy', 9500)],
            'zoneId': 'Z001',
          }, 201),
        ),
      );
      await expectLater(
        ApiQuoteRepository(api: api).quote(
          rideType: 'van',
          distanceMeters: 2500,
          pickupPoint: pickup,
          destinationPoint: dropoff,
        ),
        throwsA(isA<QuoteCategoryNotOffered>()),
      );
    });

    test('a booked quote is not reused: the route is priced again', () async {
      var calls = 0;
      final api = ApiClient(
        env: staging,
        client: MockClient((_) async {
          calls++;
          return json({
            'quotes': [quote('qte_e$calls', 'economy', 9500)],
            'zoneId': 'Z001',
          }, 201);
        }),
      );
      final repository = ApiQuoteRepository(api: api);
      final first = await repository.quote(
        rideType: 'economy',
        distanceMeters: 1,
        pickupPoint: pickup,
        destinationPoint: dropoff,
      );
      ApiQuoteRepository.markBooked(first.id);
      final second = await repository.quote(
        rideType: 'economy',
        distanceMeters: 1,
        pickupPoint: pickup,
        destinationPoint: dropoff,
      );
      expect(calls, 2);
      expect(second.id, isNot(first.id));
    });

    test(
      'a server refusal is the quote failing, never a made-up price',
      () async {
        final api = ApiClient(
          env: staging,
          client: MockClient(
            (_) async => json({
              'code': 'forbidden',
              'message': 'Movera is not available here yet.',
              'reason': 'service_not_available',
            }, 403),
          ),
        );
        await expectLater(
          ApiQuoteRepository(api: api).quote(
            rideType: 'economy',
            distanceMeters: 1,
            pickupPoint: pickup,
            destinationPoint: dropoff,
          ),
          throwsA(anything),
        );
      },
    );
  });

  group('booking', () {
    test('POST /trips sends a CreateTripRequest for the held quote', () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        env: staging,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/v1/quotes') {
            return json({
              'quotes': [quote('qte_book', 'economy', 9500)],
              'zoneId': 'Z001',
            }, 201);
          }
          return json(trip(), 201);
        }),
      );
      final quoted = await ApiQuoteRepository(api: api).quote(
        rideType: 'economy',
        distanceMeters: 2500,
        pickup: 'Sergels torg',
        destination: 'Medborgarplatsen',
        pickupPoint: pickup,
        destinationPoint: dropoff,
      );
      final booking = BookingCoordinator(api: api);

      final id = await booking.submitFinding(
        pickupAddress: 'Sergels torg',
        destinationAddress: 'Medborgarplatsen',
        pickupLat: 59.3326,
        pickupLng: 18.0649,
        destinationLat: 59.3143,
        destinationLng: 18.0735,
        rideType: 'economy',
        price: 95,
        paymentMethod: 'cash',
        quoteId: quoted.id,
        quoteExpiresAt: quoted.expiresAt,
        quoteTotalMinor: quoted.totalMinor,
        quoteCurrency: quoted.currency,
        notes: const RideNotes(bags: true, pet: true),
      );

      expect(id, 'trp_1');
      final create = requests.last;
      expect(create.method, 'POST');
      expect(create.url.path, '/api/v1/trips');
      expect(create.headers['Idempotency-Key'], isNotNull);
      final body = jsonDecode(create.body) as Map<String, dynamic>;
      expect(body, {
        'quoteId': 'qte_book',
        'categoryId': 'economy',
        'pickup': {'lat': 59.3326, 'lng': 18.0649, 'address': 'Sergels torg'},
        'dropoff': {
          'lat': 59.3143,
          'lng': 18.0735,
          'address': 'Medborgarplatsen',
        },
        'stops': <Object>[],
        'kind': 'live',
        'paymentMethod': 'cash',
        'notes': 'Bags, Pet',
      });
      // The created trip is the session's, with its first version.
      expect(AppScope.instance.ride.rideId, 'trp_1');
      expect(AppScope.instance.ride.status, RideStatus.findingDriver);
      expect(AppScope.instance.ride.projectionVersionOf('trp_1'), 3);
      expect((await RideSnapshotStore.read())?.rideId, 'trp_1');
    });

    test('the payment brands map to contract PaymentMethod values', () {
      expect(BookingCoordinator.contractPaymentMethod('cash'), 'cash');
      expect(BookingCoordinator.contractPaymentMethod('apple'), 'apple_pay');
      expect(BookingCoordinator.contractPaymentMethod('google'), 'google');
      expect(BookingCoordinator.contractPaymentMethod('card:pm_1'), 'card');
      final body = BookingCoordinator.contractTripBody(
        quoteId: 'qte_unknown',
        categoryId: 'movera',
        paymentMethod: 'card:pm_1',
        pickupLat: 1,
        pickupLng: 2,
        destinationLat: 3,
        destinationLng: 4,
        walletFirst: true,
      );
      expect(body['categoryId'], 'economy');
      expect(body['paymentMethod'], 'card');
      expect(body['paymentMethodId'], 'pm_1');
      expect(body['walletFirst'], isTrue);
      expect(body['pickup'], {'lat': 1.0, 'lng': 2.0});
      expect(body.containsKey('notes'), isFalse);
    });

    test(
      'the rider cancel goes out with expectedVersion and a reasonCode',
      () async {
        final requests = <http.Request>[];
        final api = ApiClient(
          env: staging,
          client: MockClient((request) async {
            requests.add(request);
            return json(
              trip(
                status: 'cancelled_by_rider',
                version: 4,
                cancellation: {
                  'actor': 'rider',
                  'reasonCode': 'something_else',
                  'fee': null,
                },
              ),
            );
          }),
        );
        AppScope.instance.ride.observeProjectionVersion('trp_1', 3);
        await BookingCoordinator(
          api: api,
        ).cancel(rideId: 'trp_1', key: 'cancel-key-0123456789');
        final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
        expect(requests.single.url.path, '/api/v1/rides/trp_1/cancel');
        expect(body['expectedVersion'], 3);
        expect(body['reasonCode'], 'something_else');
      },
    );

    test(
      'end-early and rating use the /trips paths movera-server serves',
      () async {
        final requests = <http.Request>[];
        final api = ApiClient(
          env: staging,
          client: MockClient((request) async {
            requests.add(request);
            return json({
              'tripId': 'trp_1',
              'from': 'rider',
              'stars': 5,
              'tags': <Object>[],
            }, 201);
          }),
        );
        expect(
          api.tripPath('trp_1', PendingCancelCommand.endEarly.pathSegment),
          '/api/v1/trips/trp_1/end-early',
        );
        await RideFeedbackRepository(api: api).submit(
          rideId: 'trp_1',
          rating: 5,
          idempotencyKey: 'rating-key-0123456789',
        );
        expect(requests.single.url.path, '/api/v1/trips/trp_1/rating');
        expect(jsonDecode(requests.single.body), {'stars': 5});
        // The mock keeps its own paths.
        expect(
          ApiClient(
            client: MockClient((_) async => json({})),
          ).tripPath('r1', 'end-early'),
          '/api/v1/rides/r1/end-early',
        );
      },
    );
  });

  group('reads', () {
    test(
      'GET /rider/trips/active: 204 is no trip, a bare projection is it',
      () async {
        var answer = http.Response('', 204);
        final api = ApiClient(
          env: staging,
          client: MockClient((_) async => answer),
        );
        final repository = ApiActiveTripRepository(api: api);
        expect(await repository.fetchActive(), isNull);

        answer = json(trip(status: 'accepted', version: 5, driver: driver));
        final active = await repository.fetchActive();
        expect(active?.rideId, 'trp_1');
        expect(active?.status, RideStatus.driverAssigned);
        expect(active?.version, 5);
        expect(active?.price, 95);
        expect(active?.driver?.firstName, 'Test');
        expect(active?.driver?.plate, 'TST 001');
        expect(active?.pickupAddress, 'Sergels torg');
        expect(active?.destinationLat, 59.3143);
      },
    );

    test(
      'a completed trip waits for the rating; history reads TripPage items',
      () async {
        final api = ApiClient(
          env: staging,
          client: MockClient(
            (_) async => json({
              'items': [
                trip(
                  status: 'completed',
                  version: 10,
                  driver: driver,
                  paymentStatus: 'captured',
                  ratingStatus: 'pending',
                ),
              ],
              'nextCursor': null,
            }),
          ),
        );
        final history = await ApiRideHistoryRepository(api: api).loadOnDemand();
        expect(history, hasLength(1));
        expect(history.single.reservationId, 'ondemand-trp_1');
      },
    );

    test(
      'GET /payment-methods reads the contract page and its default',
      () async {
        final api = ApiClient(
          env: staging,
          client: MockClient(
            (_) async => json({
              'items': [
                {
                  'paymentMethodId': 'cash',
                  'method': 'cash',
                  'isDefault': true,
                },
              ],
              'nextCursor': null,
            }),
          ),
        );
        final repository = ApiPaymentMethodRepository(api: api);
        final methods = await repository.listMethods();
        expect(methods.single.id, 'cash');
        expect(methods.single.label, 'Cash');
        expect(await repository.read(), 'cash');
      },
    );
  });
}
