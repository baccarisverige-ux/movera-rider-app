import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/server_clock.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';

void main() {
  RideSelectionController controller() => RideSelectionController(
    store: RideSelectionRepository(),
    quotes: CatalogQuoteRepository(),
  );

  test('fresh quote remains authoritative before expiry', () {
    final selection = controller();
    final now = DateTime(2026, 9, 16, 10);
    selection.offeredPrices['economy'] = 249;
    selection.quoteIds['economy'] = 'q-fresh';
    selection.quoteExpiresAt['economy'] = now.add(const Duration(seconds: 30));

    expect(selection.priceFor('economy', 259, now: now), 249);
    expect(selection.quoteIdFor('economy', now: now), 'q-fresh');
    expect(selection.quoteIsFresh('economy', now: now), isTrue);
  });

  test(
    'expired quote is discarded instead of showing or submitting stale fare',
    () {
      final selection = controller();
      final now = DateTime(2026, 9, 16, 10);
      selection.offeredPrices['economy'] = 199;
      selection.quoteIds['economy'] = 'q-expired';
      selection.quoteExpiresAt['economy'] = now.subtract(
        const Duration(seconds: 1),
      );

      expect(selection.priceFor('economy', 259, now: now), 259);
      expect(selection.offeredPrices.containsKey('economy'), isFalse);
      expect(selection.quoteIdFor('economy', now: now), isNull);
      expect(selection.quoteExpiresAt.containsKey('economy'), isFalse);
    },
  );

  test('catalog selection without a server quote is not authoritative', () {
    final selection = controller();
    selection.selectRide('xl', 399);

    expect(selection.priceFor('xl', 399), 399);
    expect(selection.quoteIsFresh('xl'), isFalse);
    expect(selection.quoteIsAvailable('xl'), isFalse);
  });

  test('rider-r4-32: a quote is judged on the server clock, so a phone '
      'three minutes fast still shows and books it', () async {
    addTearDown(ServerClock.reset);
    final server = DateTime.now().toUtc().subtract(const Duration(minutes: 3));
    final api = ApiClient(
      env: AppEnv.current,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'quote': {
              'quoteId': 'q-skew',
              'rideType': 'economy',
              'total': {'amountMinor': 24900, 'currency': 'SEK'},
              'signedPayload': 'signed',
              'expiresAt': server
                  .add(const Duration(minutes: 2))
                  .toIso8601String(),
            },
          }),
          200,
          headers: {'date': HttpDate.format(server)},
        ),
      ),
    );
    final quote = await ApiQuoteRepository(
      api: api,
    ).quote(rideType: 'economy', distanceMeters: 3000);
    final selection = controller()..adoptQuote('economy', quote);

    expect(selection.quoteIsFresh('economy'), isTrue);
    expect(selection.priceFor('economy', 259), 249);
  });
}
