import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/ride_details_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v0.18.143 (owner 2026-11-20 "must rider can change !!!!", contract
/// onTrip.routeChange.whileSearching; approved mockup screens 1–5a): while
/// the ride is searched the rider changes the pickup to ANY place.
/// 2 Ride details (price, pay in car, pencils, +), 3 the route screen with
/// the pickup open, 4 "Your price has changed" → Confirm new price,
/// 5a the server applies it at once (pickup, price) and searches again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => L10n.use('en'));

  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  Map<String, Object> money(int minor) => {
    'amountMinor': minor,
    'currency': 'SEK',
  };
  RideSnapshot ride() => RideSnapshot(
    status: RideStatus.findingDriver,
    savedAt: DateTime.now(),
    pickupAddress: 'Sergels torg',
    destinationAddress: 'Arlanda Airport',
    pickupLat: 59.3326,
    pickupLng: 18.0649,
    destinationLat: 59.65,
    destinationLng: 17.93,
    rideType: 'Movera',
    price: 600,
    currency: 'SEK',
    paymentMethod: 'Cash',
    rideId: 'trp_1',
  );

  test(
    'searching: the route-quote carries the new pickup; the accepted change moves the saved pickup',
    () async {
      final calls = <http.Request>[];
      final api = ApiClient(
        env: live,
        client: MockClient((request) async {
          calls.add(request);
          if (request.url.path.endsWith('/route-quote')) {
            return http.Response(
              jsonEncode({
                'routeQuoteId': 'rq_1',
                'tripId': 'trp_1',
                'total': money(28000),
                'difference': money(-32000),
                'expiresAt': '2099-01-01T00:00:00Z',
              }),
              201,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'tripId': 'trp_1',
              'version': 6,
              'status': 'searching',
              'routeChange': {
                'changeId': 'rc_1',
                'status': 'accepted',
                'answeredBy': 'system',
                'reason': 'rider_changed_route',
                'pickup': {
                  'lat': 59.6,
                  'lng': 17.9,
                  'address': 'Klockarvägen 37',
                },
                'dropoff': {
                  'lat': 59.33,
                  'lng': 18.06,
                  'address': 'T-Centralen',
                },
                'stops': <Object>[],
                'total': money(28000),
                'difference': money(-32000),
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final changes = RouteChangeController(
        api: api,
        geocoding: _Geo(),
        zoneAllows: true,
        maxStops: 3,
      );
      final quote = await changes.preview(
        ride: ride(),
        pickupAddress: 'Klockarvägen 37',
        pickupPoint: const GeoPoint(59.6, 17.9),
        destinationAddress: 'T-Centralen',
        destinationPoint: const GeoPoint(59.33, 18.06),
      );
      final body = jsonDecode(calls.first.body) as Map;
      expect(body['pickup'], {
        'lat': 59.6,
        'lng': 17.9,
        'address': 'Klockarvägen 37',
      });
      expect(quote.pickupAddress, 'Klockarvägen 37');
      final change = await changes.propose(ride: ride(), quote: quote);
      expect(change!.accepted, isTrue);
      expect(change.pickup?.address, 'Klockarvägen 37');
      final saved = await RouteChangeController.adoptAccepted(ride(), change);
      expect(saved.pickupAddress, 'Klockarvägen 37');
      expect(saved.pickupLat, 59.6);
      expect(saved.price, 280);
    },
  );

  test(
    'the pickup unchanged: no pickup in the route-quote (as before)',
    () async {
      final calls = <http.Request>[];
      final api = ApiClient(
        env: live,
        client: MockClient((request) async {
          calls.add(request);
          return http.Response(
            jsonEncode({
              'routeQuoteId': 'rq_1',
              'total': money(60000),
              'difference': money(0),
              'expiresAt': '2099-01-01T00:00:00Z',
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await RouteChangeController(
        api: api,
        geocoding: _Geo(),
        zoneAllows: true,
      ).preview(
        ride: ride(),
        destinationAddress: 'T-Centralen',
        destinationPoint: const GeoPoint(59.33, 18.06),
      );
      expect(
        (jsonDecode(calls.single.body) as Map).containsKey('pickup'),
        isFalse,
      );
    },
  );

  testWidgets(
    '2. Ride details: price, Pay in car, pickup pencil while searching, destination pencil and +',
    (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideDetailsSheet(
              pickupAddress: 'Klockarvägen 37',
              destinationAddress: 'Arlanda Airport',
              rideType: 'Movera',
              price: 600,
              currency: 'SEK',
              paymentMethod: 'Cash',
              notes: const RideNotes(),
              onCancelTrip: () => taps.add('cancel'),
              onEditPickup: () => taps.add('pickup'),
              onEditDestination: () => taps.add('destination'),
              onAddStop: () => taps.add('stop'),
            ),
          ),
        ),
      );
      expect(find.textContaining('600'), findsOneWidget);
      expect(find.text(L10n.current.payCash), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ride-details-edit-pickup')));
      await tester.tap(
        find.byKey(const ValueKey('ride-details-edit-destination')),
      );
      await tester.tap(find.byKey(const ValueKey('ride-details-add-stop')));
      expect(taps, ['pickup', 'destination', 'stop']);
    },
  );

  testWidgets('2. after a driver accepted: no pickup pencil', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideDetailsSheet(
            pickupAddress: 'Klockarvägen 37',
            destinationAddress: 'Arlanda Airport',
            rideType: 'Movera',
            price: 600,
            paymentMethod: 'Cash',
            notes: const RideNotes(),
            onCancelTrip: () {},
            onEditDestination: () {},
            onAddStop: () {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('ride-details-edit-pickup')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ride-details-edit-destination')),
      findsOneWidget,
    );
  });

  for (final language in ['en', 'sv', 'fr']) {
    testWidgets('4. Your price has changed → Confirm new price ($language)', (
      tester,
    ) async {
      L10n.use(language);
      RouteChangeDecision? decision;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    decision = await RouteChangeSheet.confirm(
                      context,
                      paymentMethod: 'Cash',
                      quote: RouteChangeQuote(
                        pickupAddress: 'Klockarvägen 37',
                        pickupPoint: const GeoPoint(59.6, 17.9),
                        destinationAddress: 'T-Centralen',
                        destinationPoint: const GeoPoint(59.33, 18.06),
                        stops: const [],
                        oldPriceKr: 600,
                        newPriceKr: 280,
                        currency: 'SEK',
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(L10n.current.priceChangedTitle), findsOneWidget);
      expect(find.text(L10n.current.cancel), findsOneWidget);
      await tester.tap(find.text(L10n.current.confirmNewPrice));
      await tester.pumpAndSettle();
      expect(decision?.confirmed, isTrue);
    });
  }
}

class _Geo implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async => null;
  @override
  Future<String?> reverse(GeoPoint point) async => null;
}
