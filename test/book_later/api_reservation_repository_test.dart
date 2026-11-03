import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/favourites/favourite_drivers.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/data/disabled_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_errors.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';

/// Contract v0.18.17 Book later (owner 2026-11-03 "Build it for real"): on
/// live a booked ride is the server's trip of kind scheduled. Before, the
/// live app refused every booking (DisabledReservationRepository).
void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );
  final at = DateTime.utc(2026, 11, 5, 8);
  const pickup = ReservationPlace(
    label: 'Sergels torg',
    lat: 59.3326,
    lng: 18.0649,
  );
  const dropoff = ReservationPlace(
    label: 'Medborgarplatsen',
    lat: 59.3143,
    lng: 18.0735,
  );

  Map<String, Object?> trip(
    String status, {
    int version = 2,
    int fare = 24200,
  }) => {
    'tripId': 'trp_1',
    'kind': 'scheduled',
    'status': status,
    'version': version,
    'categoryId': 'economy',
    'scheduledAt': '2026-11-05T08:00:00Z',
    'createdAt': '2026-11-05T05:00:00Z',
    'pickup': {'address': 'Sergels torg', 'lat': 59.3326, 'lng': 18.0649},
    'dropoff': {'address': 'Medborgarplatsen', 'lat': 59.3143, 'lng': 18.0735},
    'stops': <Object>[],
    'fare': {'amountMinor': fare, 'currency': 'SEK'},
    'paymentMethod': 'cash',
    if (status == 'accepted')
      'driver': {'driverId': 'drv_1', 'firstName': 'Ali'},
  };

  late List<http.Request> requests;
  ApiReservationRepository repo(
    Map<String, Object?> Function(http.Request) answer, {
    int status = 200,
  }) {
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      final body = answer(request);
      final code = body['code'] != null
          ? (body['status'] as int? ?? 400)
          : (request.url.path == '/api/v1/trips' ? 201 : 200);
      return http.Response(
        jsonEncode(body),
        code,
        headers: {'content-type': 'application/json'},
      );
    });
    return ApiReservationRepository(
      api: ApiClient(client: client, env: staging),
    );
  }

  ReservationDraft draft({double price = 242}) => ReservationDraft(
    scheduledPickupAt: at,
    pickup: pickup,
    destination: dropoff,
    categoryId: 'economy',
    categoryName: 'Economy',
    categoryImage: '',
    price: price,
    paymentMethod: 'Cash',
  );

  Map<String, Object?> quotes(int total) => {
    'quotes': [
      {
        'quoteId': 'qte_1',
        'categoryId': 'economy',
        'total': {'amountMinor': total, 'currency': 'SEK'},
      },
    ],
  };

  test(
    'release builds book later on the server; the stand-in stays for Book later off',
    () {
      expect(FeatureFlags.release.bookingLater, isTrue);
      expect(FeatureFlags.release.scheduledRides, isTrue);
      expect(repo((_) => {}), isA<ServerBackedRepository>());
      expect(DisabledReservationRepository(), isA<FeatureOffRepository>());
    },
  );

  test(
    'booking asks a scheduled quote and books it (POST /quotes kind scheduled, POST /trips)',
    () async {
      final r = repo(
        (req) => req.url.path == '/api/v1/quotes'
            ? quotes(24200)
            : trip('requested'),
      );
      final booked = await r.createReservation(draft());
      expect(booked.reservationId, 'trp_1');
      expect(booked.status, ReservationStatus.scheduled);
      expect(booked.price, 242);
      final quote = jsonDecode(requests[0].body) as Map<String, dynamic>;
      expect(quote['kind'], 'scheduled');
      expect(quote['scheduledAt'], '2026-11-05T08:00:00.000Z');
      expect(quote['categoryIds'], ['economy']);
      final book = jsonDecode(requests[1].body) as Map<String, dynamic>;
      expect(book, containsPair('quoteId', 'qte_1'));
      expect(book, containsPair('kind', 'scheduled'));
      expect(book, containsPair('paymentMethod', 'cash'));
    },
  );

  test(
    'a different server price is never booked silently: the rider sees the new price first',
    () async {
      final r = repo((req) => quotes(26700));
      await expectLater(
        r.createReservation(draft()),
        throwsA(isA<ScheduledQuoteRequiredException>()),
      );
      expect(requests.where((q) => q.url.path == '/api/v1/trips'), isEmpty);
    },
  );

  test(
    'change = new quote + reschedule; under the free-change time the server says no',
    () async {
      final r = repo(
        (req) => switch (req.url.path) {
          '/api/v1/quotes' => quotes(26700),
          '/api/v1/trips/trp_1' => trip('accepted', version: 4),
          _ => trip('requested', version: 6, fare: 26700),
        },
      );
      final changed = await r.updateReservation(
        'trp_1',
        const ReservationPatch(price: 267),
      );
      expect(changed.price, 267);
      expect(requests.last.url.path, '/api/v1/trips/trp_1/reschedule');
      expect(jsonDecode(requests.last.body), {
        'quoteId': 'qte_1',
        'expectedVersion': 4,
      });

      final late = repo(
        (req) => switch (req.url.path) {
          '/api/v1/quotes' => quotes(26700),
          '/api/v1/trips/trp_1' => trip('accepted', version: 4),
          _ => {
            'code': 'conflict',
            'message':
                'A booked ride can be changed only more than 60 minutes before pickup.',
            'reason': 'change_too_late',
            'status': 409,
          },
        },
      );
      Object? error;
      try {
        await late.updateReservation(
          'trp_1',
          const ReservationPatch(price: 267),
        );
      } catch (e) {
        error = e;
      }
      expect(error, isA<BookLaterRefusedException>());
      expect((error! as BookLaterRefusedException).limit, 60);
    },
  );

  test(
    'cancel sends the trip version and a rider reason; the list is the server\'s',
    () async {
      final r = repo(
        (req) => switch (req.url.path) {
          '/api/v1/rider/trips' => {
            'items': [
              trip('accepted'),
              {...trip('requested'), 'tripId': 'trp_live', 'kind': 'live'},
            ],
            'nextCursor': null,
          },
          '/api/v1/trips/trp_1' => trip('accepted', version: 3),
          _ => {
            ...trip('cancelled_by_rider', version: 4),
            'cancellation': {
              'actor': 'rider',
              'at': '2026-11-05T06:00:00Z',
              'fee': null,
            },
          },
        },
      );
      final upcoming = await r.getUpcomingReservations();
      expect(upcoming.map((x) => x.reservationId), [
        'trp_1',
      ], reason: 'only booked rides');
      expect(upcoming.single.driver?.firstName, 'Ali');
      expect(upcoming.single.status, ReservationStatus.driverAssigned);
      final cancelled = await r.cancelReservation('trp_1', reason: 'anything');
      expect(cancelled.status, ReservationStatus.cancelled);
      expect(jsonDecode(requests.last.body), {
        'expectedVersion': 2,
        'reasonCode': 'plans_changed',
      });
    },
  );

  test('the zone\'s rules come back in plain words', () {
    expect(
      reservationErrorMessage(
        const BookLaterRefusedException('booking_too_soon', limit: 15),
        ReservationAction.book,
      ),
      contains('15'),
    );
    expect(
      reservationErrorMessage(
        const BookLaterRefusedException('booking_too_far', limit: 90),
        ReservationAction.book,
      ),
      contains('90'),
    );
    expect(
      reservationErrorMessage(
        const BookLaterRefusedException('change_too_late', limit: 60),
        ReservationAction.edit,
      ),
      contains('60'),
    );
  });

  test(
    'the rider config reads the zone\'s booking window (15 min to 90 days, free change 60)',
    () {
      final config = RiderAppConfig.fromJson({
        'version': 2,
        'publishedAt': '2026-11-01T00:00:00Z',
        'zoneId': 'Z001',
        'currency': 'SEK',
        'timeZone': 'Europe/Stockholm',
        'booking': {
          'bookingHorizonDays': 7,
          'minAheadMin': 20,
          'maxAheadDays': 90,
          'freeChangeBeforeMin': 120,
        },
      });
      expect(config!.bookingHorizonDays, 90);
      expect(config.minAheadMin, 20);
      expect(config.freeChangeBeforeMin, 120);
    },
  );

  test(
    'owner BL-Q4: a favourite driver is the driver of the trip, saved on the server',
    () async {
      final calls = <http.Request>[];
      final api = ApiClient(
        client: MockClient((r) async {
          calls.add(r);
          final body = r.url.path.startsWith('/api/v1/trips/')
              ? trip('completed')
              : {
                  'items': [
                    {'driverId': 'drv_1', 'firstName': 'Ali'},
                  ],
                };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        env: staging,
      );
      final favs = FavouriteDrivers(api);
      final completed = {
        ...trip('completed'),
        'driver': {'driverId': 'drv_1', 'firstName': 'Ali'},
      };
      final api2 = ApiClient(
        client: MockClient((r) async {
          calls.add(r);
          return http.Response(
            jsonEncode(
              r.url.path.startsWith('/api/v1/trips/')
                  ? completed
                  : {
                      'items': [
                        {'driverId': 'drv_1'},
                      ],
                    },
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        env: staging,
      );
      expect(await FavouriteDrivers(api2).driverOfTrip('trp_1'), 'drv_1');
      expect(await FavouriteDrivers(api2).set('drv_1', favourite: true), [
        'drv_1',
      ]);
      expect(calls.last.method, 'PUT');
      expect(calls.last.url.path, '/api/v1/rider/favourite-drivers/drv_1');
      expect(
        await favs.driverOfTrip('trp_1'),
        isNull,
        reason: 'no driver on the trip',
      );
    },
  );

  test(
    'owner BL-Q6: changing a taken ride keeps the driver while he is asked',
    () async {
      final r = repo(
        (req) => switch (req.url.path) {
          '/api/v1/quotes' => quotes(26700),
          '/api/v1/trips/trp_1' => trip('accepted', version: 4),
          _ => {
            ...trip('accepted', version: 5, fare: 26700),
            'reservation': {
              'mode': 'list',
              'changeAsk': {
                'until': '2026-11-05T05:15:00Z',
                'previousAt': '2026-11-05T08:00:00Z',
              },
            },
          },
        },
      );
      final changed = await r.updateReservation(
        'trp_1',
        const ReservationPatch(price: 267),
      );
      expect(changed.status, ReservationStatus.driverAssigned);
      expect(changed.driver?.firstName, 'Ali');
    },
  );

  test(
    'a booked ride shows its pickup in its zone\'s time: Stockholm, Paris, Tunis (owner Q7)',
    () {
      final july = DateTime.utc(2026, 7, 5, 7);
      expect(zoneWallTime(july, 'Europe/Stockholm').hour, 9);
      expect(zoneWallTime(july, 'Europe/Paris').hour, 9);
      expect(zoneWallTime(july, 'Africa/Tunis').hour, 8);
      final booked = ApiReservationRepository.reservationOfTrip(
        Map<String, dynamic>.from(trip('requested')),
        draft: ReservationDraft(
          scheduledPickupAt: at,
          pickup: pickup,
          destination: dropoff,
          categoryId: 'economy',
          categoryName: 'Economy',
          categoryImage: '',
          price: 242,
          paymentMethod: 'Cash',
          timeZone: 'Africa/Tunis',
        ),
      );
      expect(
        booked.pickupWallTime.hour,
        9,
        reason: '08:00 UTC is 09:00 in Tunis in November',
      );
    },
  );
}
