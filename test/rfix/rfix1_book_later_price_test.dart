import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _origin = LatLng(59.3293, 18.0686);

/// A stand-in for movera-server's `POST /quotes` and `POST /trips`: a ride
/// now costs 176 kr, the same ride booked for later 204 kr (reservation fee
/// 25 kr and the app fee on it), as in the 2026-11-19 click-through. The
/// app only ever shows and books what this "server" answers.
class _Server {
  final List<Map<String, dynamic>> quoteBodies = [];
  final List<Map<String, dynamic>> tripBodies = [];
  final Map<String, int> _totals = {};
  final Map<String, String?> _kinds = {};
  int _n = 0;

  /// What the server adds to every price from now on (its prices moved).
  int extra = 0;

  static int live(String category) => switch (category) {
    'economy' => 17600,
    'comfort' => 22000,
    _ => 26500,
  };

  http.Client get client => MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path == '/api/v1/quotes') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      quoteBodies.add(body);
      final scheduled = body['kind'] == 'scheduled';
      final wanted =
          (body['categoryIds'] as List?)?.cast<String>() ??
          const ['economy', 'comfort', 'xl'];
      return _json({
        'quotes': [
          for (final category in wanted)
            () {
              final id = 'qte_${++_n}';
              final total = live(category) + (scheduled ? 2800 : 0) + extra;
              _totals[id] = total;
              _kinds[id] = scheduled ? body['scheduledAt'] as String : null;
              return {
                'quoteId': id,
                'categoryId': category,
                'total': {'amountMinor': total, 'currency': 'SEK'},
                'fareLines': <Object>[],
                'expiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 5))
                    .toIso8601String(),
                'pickup': body['pickup'],
                'dropoff': body['dropoff'],
                'stops': body['stops'],
                'pickupAt': scheduled ? body['scheduledAt'] : null,
              };
            }(),
        ],
      });
    }
    if (request.method == 'POST' && path == '/api/v1/trips') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      tripBodies.add(body);
      final id = body['quoteId'] as String;
      // movera-server src/trips/service.ts: the trip's kind and time must
      // be the quote's (`quote_mismatch`).
      if (_kinds[id] != body['scheduledAt']) {
        return _json({
          'code': 'bad_request',
          'reason': 'quote_mismatch',
          'message': 'The ride does not match its price.',
        }, 400);
      }
      return _json({
        'tripId': 'trp_1',
        'kind': 'scheduled',
        'status': 'requested',
        'version': 1,
        'categoryId': body['categoryId'],
        'scheduledAt': body['scheduledAt'],
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'pickup': body['pickup'],
        'dropoff': body['dropoff'],
        'stops': body['stops'],
        'fare': {'amountMinor': _totals[id], 'currency': 'SEK'},
        'paymentMethod': body['paymentMethod'],
      }, 201);
    }
    return _json({'code': 'not_found', 'message': 'no such route'}, 404);
  });

  static http.Response _json(Map<String, Object?> body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// R1 (owner 2026-11-20, "Yes, all 7 as drafts"): Choose your ride showed
/// the price of a ride now (176 kr) for a ride booked for later, which the
/// server books at 204 kr; the rider saw 204 kr only after booking.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.example.test',
  );

  Future<({RideSelectionController selection, ReservationController booked})>
  pumpSelectRide(
    WidgetTester tester,
    _Server server, {
    DateTime? scheduledFor,
  }) async {
    final api = ApiClient(client: server.client, env: staging);
    final selection = RideSelectionController(
      catalog: RideCatalogController(api: api, cache: MemoryRideCatalogCache()),
      quotes: ApiQuoteRepository(api: api),
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    final reservations = ReservationController(
      store: ApiReservationRepository(api: api),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Drottninggatan 1, Stockholm',
          destinationAddress: 'Solna Centrum, Solna torg',
          pickupPosition: _origin,
          destinationPosition: const LatLng(59.3600, 18.0000),
          selection: selection,
          reservations: reservations,
          initialScheduledFor: scheduledFor,
        ),
      ),
    );
    await settle(tester);
    return (selection: selection, booked: reservations);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('a ride opened as Book later lists the booked-ride price', (
    tester,
  ) async {
    final server = _Server();
    await pumpSelectRide(
      tester,
      server,
      scheduledFor: StockholmSchedule.clampPickup(
        StockholmSchedule.stockholmNow().add(const Duration(days: 1)),
      ),
    );
    expect(find.text('204,00 kr'), findsWidgets);
    expect(find.text('176,00 kr'), findsNothing);
    await close(tester);
  });

  testWidgets(
    'choosing Book for later on Choose your ride prices the list again as a '
    'booked ride, and that price is the one booked',
    (tester) async {
      final server = _Server();
      final app = await pumpSelectRide(tester, server);
      expect(find.text('176,00 kr'), findsWidgets);

      await tester.tap(find.bySemanticsLabel(RegExp('Book now or later')));
      await settle(tester);
      await tester.tap(find.text('Book for later'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester, 20);

      // The list now shows what the server charges for the booked ride.
      expect(find.text('Schedule Movera'), findsOneWidget);
      expect(find.text('204,00 kr'), findsWidgets);
      expect(find.text('176,00 kr'), findsNothing);
      expect(server.quoteBodies.last['kind'], 'scheduled');

      await tester.tap(find.text('Schedule Movera'));
      await settle(tester, 30);
      // Set pickup shows the same price, before the rider confirms.
      expect(find.text('204,00 kr'), findsWidgets);
      expect(find.text('176,00 kr'), findsNothing);
      await tester.tap(find.text('Confirm and schedule'));
      await settle(tester, 40);

      expect(app.booked.all, hasLength(1));
      expect(app.booked.all.single.price, 204);
      expect(server.tripBodies, hasLength(1));
      await close(tester);
    },
  );

  testWidgets('going back to Book now prices the list again as a ride now', (
    tester,
  ) async {
    final server = _Server();
    await pumpSelectRide(
      tester,
      server,
      scheduledFor: StockholmSchedule.clampPickup(
        StockholmSchedule.stockholmNow().add(const Duration(days: 1)),
      ),
    );
    expect(find.text('204,00 kr'), findsWidgets);
    await tester.tap(find.bySemanticsLabel(RegExp('Book now or later')));
    await settle(tester);
    await tester.tap(find.text('Book now'));
    await settle(tester, 20);
    expect(find.text('Select Movera'), findsOneWidget);
    expect(find.text('176,00 kr'), findsWidgets);
    expect(find.text('204,00 kr'), findsNothing);
    expect(server.quoteBodies.last.containsKey('kind'), isFalse);
    await close(tester);
  });

  DateTime tomorrow() => StockholmSchedule.clampPickup(
    StockholmSchedule.stockholmNow().add(const Duration(days: 1)),
  );

  testWidgets(
    'R2: the server books at another price than the one held: the rider '
    'sees the new price, agrees, and the ride is booked at it',
    (tester) async {
      final server = _Server();
      final app = await pumpSelectRide(
        tester,
        server,
        scheduledFor: tomorrow(),
      );
      await tester.tap(find.text('Schedule Movera'));
      await settle(tester, 30);
      expect(find.text('204,00 kr'), findsWidgets);
      // The server's price moves while Set pickup is open.
      server.extra = 500;
      await tester.tap(find.text('Confirm and schedule'));
      await settle(tester, 40);

      expect(app.booked.all, isEmpty);
      expect(
        find.byKey(const ValueKey('select-ride-price-updated')),
        findsOneWidget,
      );
      expect(find.textContaining('209,00 kr'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('select-ride-price-accept')));
      await settle(tester, 40);

      expect(app.booked.all, hasLength(1));
      expect(app.booked.all.single.price, 209);
      expect(server.tripBodies, hasLength(1));
      await close(tester);
    },
  );

  testWidgets(
    'R2: the rider says Not now to the new price: nothing is booked and the '
    'list shows the new price, not the one that could not be booked',
    (tester) async {
      final server = _Server();
      final app = await pumpSelectRide(
        tester,
        server,
        scheduledFor: tomorrow(),
      );
      await tester.tap(find.text('Schedule Movera'));
      await settle(tester, 30);
      server.extra = 500;
      await tester.tap(find.text('Confirm and schedule'));
      await settle(tester, 40);
      await tester.tap(find.text('Not now'));
      await settle(tester, 30);

      expect(app.booked.all, isEmpty);
      expect(server.tripBodies, isEmpty);
      expect(find.text('209,00 kr'), findsWidgets);
      expect(find.text('204,00 kr'), findsNothing);
      await close(tester);
    },
  );

  test(
    'a quote priced for another booking mode is not the price to book',
    () async {
      final api = ApiClient(client: _Server().client, env: staging);
      final selection = RideSelectionController(
        catalog: RideCatalogController(
          api: api,
          cache: MemoryRideCatalogCache(),
        ),
        quotes: ApiQuoteRepository(api: api),
        flags: FeatureFlags(),
      );
      addTearDown(selection.dispose);
      Future<void> load() => selection.loadQuotes(
        generation: selection.beginQuotes(),
        pickup: 'A',
        destination: 'B',
        pickupPoint: const GeoPoint(59.3293, 18.0686),
        destinationPoint: const GeoPoint(59.36, 18.0),
      );
      await load();
      expect(selection.quoteIsAvailable('economy'), isTrue);
      expect(selection.priceFor('economy', 0), 176);
      expect(selection.takeBookingModeRequote(), isFalse);

      // Book for later: the price of a ride now is no longer a price here.
      selection.scheduleFor(tomorrow());
      expect(selection.quoteIsAvailable('economy'), isFalse);
      expect(selection.authoritativePriceFor('economy'), isNull);
      expect(selection.quoteIdFor('economy'), isNull);
      expect(selection.takeBookingModeRequote(), isTrue);
      expect(selection.takeBookingModeRequote(), isFalse);
      await load();
      expect(selection.priceFor('economy', 0), 204);
      expect(selection.quoteIsAvailable('economy'), isTrue);

      // Another pickup time is still a booked ride: the price stays (the
      // booking asks the server for that time's price and compares).
      selection.scheduleFor(tomorrow().add(const Duration(hours: 1)));
      expect(selection.quoteIsAvailable('economy'), isTrue);
      expect(selection.takeBookingModeRequote(), isFalse);

      // Back to a ride now.
      selection.setBookingMode(BookingMode.now);
      expect(selection.takeBookingModeRequote(), isTrue);
      expect(selection.quoteIsAvailable('economy'), isFalse);
      await load();
      expect(selection.priceFor('economy', 0), 176);
      expect(selection.quoteIsAvailable('economy'), isTrue);
    },
  );
}

Future<void> settle(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
