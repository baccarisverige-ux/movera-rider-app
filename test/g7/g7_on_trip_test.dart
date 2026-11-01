import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/on_trip.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_pending_card.dart';
import 'package:movera_rider/features/active_ride/presentation/trip_terms_note.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Driver group 7 (contract v0.18.9 `onTrip`), rider side: the server's
/// ride check, the route change with the driver's answer (route-quote →
/// new price → confirm → waiting → accepted / refused / withdrawn), the
/// stop waiting price and the zone's max stops. Sweden and France.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => L10n.use('en'));

  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );

  Map<String, Object> money(int minor, String currency) => {
    'amountMinor': minor,
    'currency': currency,
  };

  RideSnapshot ride({String currency = 'SEK', int stops = 0}) => RideSnapshot(
    status: RideStatus.tripInProgress,
    savedAt: DateTime.now(),
    pickupAddress: 'Sergels torg',
    destinationAddress: 'Odenplan',
    pickupLat: 59.3326,
    pickupLng: 18.0649,
    destinationLat: 59.3429,
    destinationLng: 18.0496,
    rideType: 'Movera',
    price: 190,
    currency: currency,
    paymentMethod: 'Cash',
    rideId: 'trp_1',
  );

  ({ApiClient api, List<http.Request> calls}) server(
    http.Response Function(http.Request request) answer,
  ) {
    final calls = <http.Request>[];
    final api = ApiClient(
      env: live,
      client: MockClient((request) async {
        calls.add(request);
        return answer(request);
      }),
    );
    return (api: api, calls: calls);
  }

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  group('1. ride check from the server', () {
    test('the rider answers while answerBy has not passed', () {
      final check = TripRideCheck.fromWire({
        'checkId': 'srv_1',
        'trigger': 'long_stop',
        'askedAt': '2026-11-02T10:00:00Z',
        'answerBy': '2026-11-02T10:02:00Z',
        'answers': {'driver': 'ok'},
      })!;
      expect(check.openForRider(DateTime.utc(2026, 11, 2, 10, 1)), isTrue);
      expect(check.openForRider(DateTime.utc(2026, 11, 2, 10, 3)), isFalse);
      final answered = TripRideCheck.fromWire({
        'checkId': 'srv_1',
        'trigger': 'off_route',
        'answers': {'rider': 'need_help'},
      })!;
      expect(answered.openForRider(DateTime.utc(2026)), isFalse);
      expect(
        TripRideCheck.fromWire({'checkId': 'x', 'trigger': 'possible_crash'}),
        isNull,
      );
    });
  });

  group('2. route change during the trip', () {
    test('zone switch and max stops come from the rider config', () {
      final config = RiderAppConfig.fromJson({
        'version': 4,
        'zoneId': 'FR-PC',
        'currency': 'EUR',
        'booking': {'maxStops': 2},
        'routeChange': {'on': false, 'driverCanRefuse': true},
      })!;
      expect(config.routeChangeOn, isFalse);
      expect(config.maxStops, 2);
    });

    for (final currency in ['SEK', 'EUR']) {
      test(
        'route-quote → new price → PATCH { routeQuoteId } ($currency)',
        () async {
          final r = server((request) {
            if (request.url.path.endsWith('/route-quote')) {
              return json({
                'routeQuoteId': 'rq_1',
                'tripId': 'trp_1',
                'total': money(25000, currency),
                'difference': money(6000, currency),
                'expiresAt': '2099-01-01T00:00:00Z',
              }, 201);
            }
            return json({
              'tripId': 'trp_1',
              'version': 8,
              'routeChange': {
                'changeId': 'rc_1',
                'status': 'pending',
                'total': money(25000, currency),
                'difference': money(6000, currency),
              },
            });
          });
          final changes = RouteChangeController(
            api: r.api,
            geocoding: _Geo(),
            zoneAllows: true,
            maxStops: 3,
          );
          expect(changes.available, isTrue);
          final quote = await changes.preview(
            ride: ride(currency: currency),
            destinationAddress: 'Brommaplan',
            destinationPoint: const GeoPoint(59.3383, 17.9393),
            stops: const ['Fridhemsplan'],
            stopPoints: const [GeoPoint(59.3326, 18.0296)],
          );
          expect(r.calls.first.url.path, '/api/v1/trips/trp_1/route-quote');
          final body = jsonDecode(r.calls.first.body) as Map;
          expect(body['dropoff'], {
            'lat': 59.3383,
            'lng': 17.9393,
            'address': 'Brommaplan',
          });
          expect((body['stops'] as List).single['address'], 'Fridhemsplan');
          expect(quote.newTotalMinor, 25000);
          expect(quote.differenceMinor, 6000);
          final change = await changes.propose(
            ride: ride(currency: currency),
            quote: quote,
          );
          expect(r.calls.last.method, 'PATCH');
          expect(r.calls.last.url.path, '/api/v1/trips/trp_1');
          expect(jsonDecode(r.calls.last.body), {'routeQuoteId': 'rq_1'});
          expect(change!.pending, isTrue);
        },
      );
    }

    test('more stops than the zone allows: told before any call', () async {
      final r = server((_) => json({}));
      final changes = RouteChangeController(
        api: r.api,
        geocoding: _Geo(),
        zoneAllows: true,
        maxStops: 1,
      );
      await expectLater(
        changes.preview(
          ride: ride(),
          destinationAddress: 'Odenplan',
          destinationPoint: const GeoPoint(59.3429, 18.0496),
          stops: const ['A', 'B'],
          stopPoints: const [GeoPoint(59.1, 18.1), GeoPoint(59.2, 18.2)],
        ),
        throwsA(
          isA<RouteChangeException>()
              .having(
                (e) => e.failure,
                'failure',
                RouteChangeFailure.tooManyStops,
              )
              .having((e) => e.message, 'message', contains('1')),
        ),
      );
      expect(r.calls, isEmpty);
    });

    test('the server\'s too_many_stops names its max', () async {
      final r = server(
        (_) => json({
          'code': 'invalid_request',
          'reason': 'too_many_stops',
          'message': 'Too many stops',
          'details': ['maxStops=3'],
        }, 400),
      );
      final changes = RouteChangeController(
        api: r.api,
        geocoding: _Geo(),
        zoneAllows: true,
      );
      L10n.use('sv');
      await expectLater(
        changes.preview(
          ride: ride(),
          destinationAddress: 'Odenplan',
          destinationPoint: const GeoPoint(59.3429, 18.0496),
        ),
        throwsA(
          isA<RouteChangeException>().having(
            (e) => e.message,
            'message',
            'Du kan lägga till högst 3 stopp.',
          ),
        ),
      );
    });

    test('withdraw sends the change id', () async {
      final r = server(
        (_) => json({
          'tripId': 'trp_1',
          'version': 9,
          'routeChange': {'changeId': 'rc_1', 'status': 'withdrawn'},
        }),
      );
      final after = await RouteChangeController(
        api: r.api,
        geocoding: _Geo(),
        zoneAllows: true,
      ).withdraw(tripId: 'trp_1', changeId: 'rc_1');
      expect(
        r.calls.single.url.path,
        '/api/v1/trips/trp_1/route-change/withdraw',
      );
      expect(jsonDecode(r.calls.single.body), {'changeId': 'rc_1'});
      expect(after!.kept, isTrue);
    });

    test('an accepted change becomes the saved route', () async {
      final change = TripRouteChange.fromWire({
        'changeId': 'rc_1',
        'status': 'accepted',
        'dropoff': {'lat': 48.8443, 'lng': 2.3744, 'address': 'Gare de Lyon'},
        'stops': [
          {'lat': 48.85, 'lng': 2.35, 'address': 'Châtelet'},
        ],
        'total': money(2350, 'EUR'),
      })!;
      final updated = await RouteChangeController.adoptAccepted(
        ride(currency: 'EUR'),
        change,
      );
      expect(updated.destinationAddress, 'Gare de Lyon');
      expect(updated.stops.single.address, 'Châtelet');
      expect(updated.price, 23.5);
    });

    for (final language in ['en', 'sv', 'fr']) {
      testWidgets('waiting for the driver, with the new price ($language)', (
        tester,
      ) async {
        L10n.use(language);
        var withdrew = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RouteChangePendingCard(
                change: TripRouteChange.fromWire({
                  'changeId': 'rc_1',
                  'status': 'pending',
                  'total': money(25000, 'SEK'),
                  'difference': money(-1500, 'SEK'),
                })!,
                onWithdraw: () => withdrew = true,
              ),
            ),
          ),
        );
        expect(find.text(L10n.current.g7RouteWaiting), findsOneWidget);
        final price = tester
            .widget<Text>(
              find.byKey(const ValueKey('route-change-pending-price')),
            )
            .data!;
        expect(price, contains('250'));
        expect(price, contains('−15'));
        await tester.tap(find.byKey(const ValueKey('route-change-withdraw')));
        expect(withdrew, isTrue);
      });
    }
  });

  group('3. stop waiting price from the first minute', () {
    TripTerms terms(String currency, {int free = 0}) => TripTerms.fromWire({
      'currency': currency,
      'freeWaitMin': 3,
      'noShowAfterMin': 5,
      'waitPerMin': money(500, currency),
      'noShowFee': money(5000, currency),
      'stopFreeWaitMin': free,
      'stopWaitPerMin': money(450, currency),
    })!;

    test('paid from minute 1 (sv, SEK)', () {
      L10n.use('sv');
      expect(TripTermsLines.stopWaitLine(terms('SEK')), contains('/min'));
      expect(
        TripTermsLines.stopWaitLine(terms('SEK')),
        startsWith('Väntan vid stopp'),
      );
    });

    test('admin free minutes first (fr, EUR)', () {
      L10n.use('fr');
      final line = TripTermsLines.stopWaitLine(terms('EUR', free: 2))!;
      expect(line, startsWith('2 min gratuites'));
      expect(line, contains('4,50'));
    });

    test('an older server without the price: no line', () {
      final old = TripTerms.fromWire({
        'currency': 'SEK',
        'freeWaitMin': 3,
        'noShowAfterMin': 5,
        'waitPerMin': money(500, 'SEK'),
        'noShowFee': money(5000, 'SEK'),
      })!;
      expect(TripTermsLines.stopWaitLine(old), isNull);
      expect(Money(1, 'SEK').currency, 'SEK');
    });
  });
}

class _Geo implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}
