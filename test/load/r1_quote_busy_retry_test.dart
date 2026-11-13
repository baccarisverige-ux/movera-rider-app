import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/promotions/domain/rider_promotion.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R1 (fix plan 2026-11-13; owner 12:22 UTC "Yes, with screenshots
/// (Rec.)"; contract `fastDispatch.clients`): Select ride asks for its
/// prices again after 503 / 429 / a timeout: Retry-After (2 s), doubling up
/// to 30 s, ±20 %, at most 5 retries, then a "Try again" button. A late
/// answer is picked up without a second request.
///
/// The server under load (G34: 33-65 % of riders got no price): while
/// [busy] every quote answers `503 unavailable, reason server_busy,
/// Retry-After 2` (server src/http/shed.ts:72-75), then every ride costs
/// 412 kr.
class _BusyQuotes implements QuoteRepository {
  _BusyQuotes();

  /// While true every quote is refused busy.
  bool busy = true;
  int calls = 0;

  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) async {
    calls++;
    if (busy) {
      throw const ApiError(
        code: 'unavailable',
        reason: 'server_busy',
        message: 'The server is busy. Try again in a moment.',
        statusCode: 503,
        retryAfter: Duration(seconds: 2),
      );
    }
    return RideQuote(
      id: 'q-$rideType-$calls',
      rideType: rideType,
      totalMinor: 41200,
      currency: 'SEK',
      expiresAt: ServerClock.now().add(const Duration(minutes: 5)),
      signedPayload: 'signature',
    );
  }
}

/// A contract `POST /quotes` answer with every seed category, economy
/// 129 kr.
Map<String, dynamic> _quoteList() => {
  'quotes': [
    for (final (i, id) in CategoryIds.seed.indexed)
      {
        'quoteId': 'qte_$id',
        'categoryId': id,
        'total': {'amountMinor': 12900 + i * 1000, 'currency': 'SEK'},
        'fareLines': <Object>[],
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'pickup': {
          'address': 'Klockarvägen 37',
          'lat': 59.3293,
          'lng': 18.0686,
        },
        'dropoff': {
          'address': 'Arlanda Airport',
          'lat': 59.6519,
          'lng': 17.9186,
        },
        'stops': <Object>[],
        'surgeMultiplier': 1,
        'pickupAt': null,
      },
  ],
  'zoneId': 'Z001',
  'serverTime': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppScope.instance.promotion.value = null;
  });
  tearDown(() => AppScope.instance.promotion.value = null);

  Future<RideSelectionController> open(
    WidgetTester tester,
    QuoteRepository quotes,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selection = RideSelectionController(
      catalog: RideCatalogController(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
          ),
        ),
        cache: MemoryRideCatalogCache(),
      ),
      quotes: quotes,
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.6519, 17.9186),
          selection: selection,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return selection;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  /// Pumps [total] in 100 ms steps.
  Future<void> frames(WidgetTester tester, Duration total) async {
    for (
      var t = Duration.zero;
      t < total;
      t += const Duration(milliseconds: 100)
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  final retryButton = find.byKey(const ValueKey('select-ride-quotes-retry'));

  testWidgets('fastDispatch.clients: a 503 server_busy round of prices is '
      'asked again by itself after Retry-After, and the prices show', (
    tester,
  ) async {
    // Every price asked while the screen opens is refused busy; the server
    // is fine again 0.5 s later.
    final quotes = _BusyQuotes();
    await open(tester, quotes);
    await tester.pump(const Duration(milliseconds: 500));
    quotes.busy = false;
    final firstRound = quotes.calls;
    expect(firstRound, greaterThan(0));
    expect(find.text('412 kr'), findsNothing);

    // The server said "Retry-After 2"; the app waits that (and at most a
    // short backoff) and asks again without any tap.
    await tester.pump(const Duration(seconds: 4));
    await frames(tester, const Duration(milliseconds: 500));
    expect(quotes.calls, greaterThan(firstRound), reason: 'asked again');
    expect(find.text('412 kr'), findsWidgets);
    expect(retryButton, findsNothing);
    await close(tester);
  });

  testWidgets('a server that stays busy is not asked in a loop: at most 5 '
      'retries, spread out, then "Try again"', (tester) async {
    final quotes = _BusyQuotes();
    await open(tester, quotes);
    // Our own clock in 100 ms steps: when a burst of quote calls starts.
    final bursts = <int>[0];
    var seen = quotes.calls;
    var lastCall = 0;
    for (var t = 100; t <= 100000; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
      if (quotes.calls != seen) {
        seen = quotes.calls;
        // A new burst when the last call was more than 0.5 s ago.
        if (t - lastCall > 500) bursts.add(t);
        lastCall = t;
      }
    }
    final gaps = [
      for (var i = 1; i < bursts.length; i++) bursts[i] - bursts[i - 1],
    ];
    // Never sooner than Retry-After (2 s, less the -20 % jitter; one early
    // reload of the list when the catalog read fails is allowed), at most
    // 5 retries + that reload, and nothing in the last half minute: it
    // gave up.
    expect(
      gaps.where((g) => g < 1600).length,
      lessThanOrEqualTo(1),
      reason: 'bursts at $bursts ms',
    );
    expect(bursts.length - 1, inInclusiveRange(3, 6), reason: '$bursts');
    expect(bursts.last, lessThan(70000), reason: '$bursts');
    final stopped = quotes.calls;
    await tester.pump(const Duration(minutes: 2));
    expect(quotes.calls, stopped, reason: 'no retry after giving up');

    expect(retryButton, findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(retryButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(quotes.calls, greaterThan(stopped));
    await close(tester);
  });

  testWidgets('with a promotion line, "Try again" is still there and '
      'works; the promotion line stays', (tester) async {
    AppScope.instance.promotion.value = const RiderPromotion(
      id: 'promo-1',
      title: 'Welcome',
      percentOff: 20,
      ridesLeft: 3,
      ridesTotal: 3,
    );
    final quotes = _BusyQuotes();
    await open(tester, quotes);
    expect(
      find.byKey(const ValueKey('select-ride-promotion-line')),
      findsOneWidget,
    );
    await frames(tester, const Duration(seconds: 100));
    final stopped = quotes.calls;
    expect(retryButton, findsOneWidget);
    expect(
      find.byKey(const ValueKey('select-ride-promotion-line')),
      findsOneWidget,
    );
    await tester.tap(retryButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(quotes.calls, greaterThan(stopped));
    // The tap asked again; it did not open the promotion's details.
    expect(find.byType(BottomSheet), findsNothing);
    await close(tester);
  });

  testWidgets('a late answer (after the 8 s cut) is picked up by the retry '
      'without a second POST /quotes', (tester) async {
    var posts = 0;
    final api = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.movera.test',
      ),
      client: MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/api/v1/quotes') {
          posts++;
          // Busy pool: the answer comes after 9 s, past the screen's 8 s.
          await Future<void>.delayed(const Duration(seconds: 9));
          return http.Response(
            jsonEncode(_quoteList()),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(jsonEncode({'code': 'X'}), 500);
      }),
    );
    await open(tester, ApiQuoteRepository(api: api));
    await frames(tester, const Duration(seconds: 7));
    expect(find.text('129 kr'), findsNothing);
    // The first categories are cut at 8 s; the answer lands at 9 s; the
    // retry (2 s ± 20 % after the round) reads it from the same request.
    await frames(tester, const Duration(seconds: 8));
    expect(find.text('129 kr'), findsWidgets);
    expect(posts, 1, reason: 'one request, its late answer reused');
    expect(retryButton, findsNothing);
    await close(tester);
  });
}
