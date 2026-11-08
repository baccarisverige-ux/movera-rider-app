import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live 5+5 run 2 (2026-11-08, frame 5-rider-cancel-p5 175): Choose ride
/// showed "Movera 184 kr" with no « +35 kr obetald avgift » line, while the
/// server's `POST /quotes` answer carried `fareLines.outstanding_fee` 3500.
/// The parser read it (contractQuoteOf), but the per-category copy that
/// `ApiQuoteRepository.quote()` hands to Choose ride left the line out, so
/// the tile saw 0. The answer below is the real staging answer's shape
/// (2026-11-08, one category; ids replaced).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Live: GET /rider/outstanding is not enabled (404), so only the quote
    // tells the app about the fee.
    RiderOutstanding.reset();
  });
  tearDown(RiderOutstanding.reset);

  Map<String, dynamic> realAnswer() => {
    'quotes': [
      {
        'quoteId': 'qte_live_1',
        'categoryId': 'economy',
        'total': {'amountMinor': 12900, 'currency': 'SEK'},
        'fareLines': [
          {
            'code': 'base',
            'amount': {'amountMinor': 2900, 'currency': 'SEK'},
          },
          {
            'code': 'distance',
            'amount': {'amountMinor': 3804, 'currency': 'SEK'},
          },
          {
            'code': 'time',
            'amount': {'amountMinor': 1867, 'currency': 'SEK'},
          },
          {
            'code': 'app_fee',
            'amount': {'amountMinor': 857, 'currency': 'SEK'},
          },
          {
            'code': 'rounding',
            'amount': {'amountMinor': -28, 'currency': 'SEK'},
          },
          {
            'code': 'outstanding_fee',
            'amount': {'amountMinor': 3500, 'currency': 'SEK'},
            'sourceTripId': 'trp_earlier',
          },
        ],
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'pickup': {'address': 'Västberga', 'lat': 59.295, 'lng': 18.006},
        'dropoff': {
          'address': 'Hornstull, Stockholm',
          'lat': 59.3157,
          'lng': 18.034,
        },
        'stops': <Object>[],
        'surgeMultiplier': 1,
        'pickupAt': null,
      },
    ],
    'zoneId': 'Z001',
    'serverTime': DateTime.now().toUtc().toIso8601String(),
  };

  test(
    'the live quote answer reaches Choose ride with its +35 kr unpaid fee',
    () async {
      final api = ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.movera.test',
        ),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(realAnswer()),
            201,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final quote = await ApiQuoteRepository(api: api).quote(
        rideType: 'economy',
        distanceMeters: 3000,
        pickup: 'Västberga',
        destination: 'Hornstull, Stockholm',
        pickupPoint: const GeoPoint(59.295, 18.006),
        destinationPoint: const GeoPoint(59.3157, 18.034),
      );
      expect(quote.totalMinor, 12900);
      expect(quote.outstandingFeeMinor, 3500);

      final selection = RideSelectionController(currency: 'SEK');
      addTearDown(selection.dispose);
      selection.adoptQuote('economy', quote);
      // select_ride_tiles.dart shows « +35 kr obetald avgift » from this.
      expect(selection.unpaidFeeFor('economy'), const Money(3500, 'SEK'));
    },
  );
}
