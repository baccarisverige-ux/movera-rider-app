import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/raise_limit.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contract v0.18.6 `dispatch.raisePrice` / `RiderAppConfig.raisePrice`,
/// owner G4-E4 "2×, admin can change (Recommended)": the rider may raise
/// the fare to at most `maxFactor` × the booked fare (the zone's admin
/// setting, default 2, range 1–3); every raise button over the limit is
/// hidden, and the server's `400 raise_too_high` is handled. E5 (the
/// "Keep waiting?" steps) is not decided and is not touched here.

/// Answers every request with [handler].
class _Server extends http.BaseClient {
  _Server(this.handler);
  final http.Response Function(http.BaseRequest) handler;
  final requests = <http.BaseRequest>[];

  /// The raise requests (not the nearby-cars reads).
  Iterable<http.BaseRequest> get raises =>
      requests.where((r) => r.method != 'GET');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final r = handler(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(r.body)),
      r.statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}

RideSnapshot _ride({
  double price = 200,
  int? bookedFareMinor = 20000,
  int? maxOfferMinor,
  String currency = 'SEK',
}) => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: price,
  currency: currency,
  paymentMethod: 'Visa',
  rideId: 'ride-raise',
  bookedFareMinor: bookedFareMinor,
  maxOfferMinor: maxOfferMinor,
);

FindingDriverController _finding(http.Client client, RideSnapshot s) {
  final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
  addTearDown(rt.dispose);
  final controller = FindingDriverController(
    realtime: rt,
    ride: RideSession()..rideId = s.rideId,
    store: FindingDriverRepository(),
    api: ApiClient(client: client),
    delayedAfter: Duration.zero,
    priceBumpAfter: Duration.zero,
  );
  addTearDown(controller.dispose);
  controller.start(snapshot: s, onTick: (_) {}, onMatched: () {});
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.use('en');
  });

  group('RiderAppConfig.raisePrice.maxFactor', () {
    Map<String, Object?> doc([Object? raisePrice]) => {
      ...SeedRiderConfigRepository.seedDocument,
      'version': 40,
      'raisePrice': ?raisePrice,
    };

    test('the zone\'s factor is read; the seed and a missing one are 2', () {
      expect(SeedRiderConfigRepository.seed.raiseMaxFactor, 2);
      expect(RaiseLimit.defaultMaxFactor, 2);
      expect(
        RiderAppConfig.fromJson(doc({'maxFactor': 1.5}))!.raiseMaxFactor,
        1.5,
      );
      final missing = Map<String, Object?>.of(doc())..remove('raisePrice');
      expect(RiderAppConfig.fromJson(missing)!.raiseMaxFactor, 2);
    });

    test('a factor outside 1–3 is not used: the last good one stays', () {
      final good = RiderAppConfig.fromJson(doc({'maxFactor': 2.5}))!;
      for (final bad in [0.5, 3.5, 'two', null]) {
        expect(
          RiderAppConfig.fromJson(
            doc({'maxFactor': bad}),
            fallback: good,
          )!.raiseMaxFactor,
          2.5,
          reason: '$bad',
        );
      }
      expect(RiderAppConfig.fromJson(doc({'maxFactor': 9}))!.raiseMaxFactor, 2);
    });
  });

  group('the booked fare the limit counts from', () {
    test('quote.total when the server sends it', () {
      expect(
        RaiseLimit.bookedFareMinorOf({
          'fare': {'amountMinor': 26000, 'currency': 'SEK'},
          'quote': {
            'total': {'amountMinor': 20000, 'currency': 'SEK'},
          },
        }, 'SEK'),
        20000,
      );
    });

    test('else the fare less every rider_raise line (EUR, cents)', () {
      expect(
        RaiseLimit.bookedFareMinorOf({
          'fare': {'amountMinor': 3460, 'currency': 'EUR'},
          'fareLines': [
            {
              'code': 'base',
              'amount': {'amountMinor': 2460, 'currency': 'EUR'},
            },
            {
              'code': 'rider_raise',
              'amount': {'amountMinor': 500, 'currency': 'EUR'},
            },
            {
              'code': 'rider_raise',
              'amount': {'amountMinor': 500, 'currency': 'EUR'},
            },
          ],
        }, 'EUR'),
        2460,
      );
      expect(
        RaiseLimit.bookedFareMinorOf({
          'fare': {'amountMinor': 3460, 'currency': 'EUR'},
        }, 'SEK'),
        isNull,
      );
    });

    test('a trip projection keeps it on the snapshot, also after a reload', () {
      final snapshot = RideProjection.toSnapshot({
        'tripId': 'trp_1',
        'status': 'searching',
        'pickup': {'address': 'A', 'lat': 59.3, 'lng': 18.0},
        'dropoff': {'address': 'B', 'lat': 59.4, 'lng': 18.1},
        'fare': {'amountMinor': 25000, 'currency': 'SEK'},
        'fareLines': [
          {
            'code': 'rider_raise',
            'amount': {'amountMinor': 5000, 'currency': 'SEK'},
          },
        ],
      })!;
      expect(snapshot.bookedFareMinor, 20000);
      final again = RideSnapshot.fromJson(snapshot.toJson())!;
      expect(again.bookedFareMinor, 20000);
    });
  });

  group('the limit on the Finding screen', () {
    test('2 × the booked fare by default, the zone\'s factor when set; a '
        'raised offer does not move it', () {
      final c = _finding(InProcessMockClient(), _ride(price: 260));
      expect(c.maxOfferPrice, 400);
      c.raiseMaxFactor = 1.5;
      expect(c.maxOfferPrice, 300);
      c.raiseMaxFactor = 7; // outside the contract's range: ignored
      expect(c.maxOfferPrice, 300);
    });

    test('a fare already at the limit shows no raise card at all', () {
      final at = _finding(InProcessMockClient(), _ride(price: 400));
      expect(at.canRaise, isFalse);
      expect(at.showPriceBump, isFalse);
      final under = _finding(InProcessMockClient(), _ride(price: 399));
      expect(under.canRaise, isTrue);
      expect(under.showPriceBump, isTrue);
    });

    test('a raise over the limit is not sent and says why', () async {
      final server = _Server((_) => http.Response('{}', 500));
      final c = _finding(server, _ride(price: 300));
      expect(await c.confirmPriceIncrease(150), isFalse);
      expect(server.raises, isEmpty);
      expect(c.editFeedback, L10n.current.raiseAboveLimit);
    });

    test('400 raise_too_high: nothing changes, the rider is told, and the '
        'zone\'s config is read again', () async {
      final server = _Server(
        (_) => http.Response(
          jsonEncode({
            'code': 'invalid_request',
            'reason': 'raise_too_high',
            'message': 'The fare can be raised to at most 1.2 times.',
            'requestId': 'req_1',
            'retryable': false,
          }),
          400,
        ),
      );
      final c = _finding(server, _ride(price: 200));
      var asked = 0;
      c.onRaiseLimitRefused = () => asked++;
      expect(await c.confirmPriceIncrease(50), isFalse);
      expect(server.raises, hasLength(1));
      expect(c.currentPrice, 200);
      expect(c.editFeedback, L10n.current.raiseAboveLimit);
      expect(asked, 1);
    });
  });

  group('PriceBumpCard', () {
    Future<void> pump(WidgetTester tester, {required double max}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PriceBumpCard(
                currentPrice: 200,
                maxPrice: max,
                currency: 'SEK',
                steps: const [10, 20, 50, 100],
                onConfirm: (_) {},
                onKeepWaiting: () {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('every step that would pass the limit is hidden', (
      tester,
    ) async {
      await pump(tester, max: 240);
      expect(find.text('+10 kr'), findsOneWidget);
      expect(find.text('+20 kr'), findsOneWidget);
      expect(find.text('+50 kr'), findsNothing);
      expect(find.text('+100 kr'), findsNothing);
    });

    testWidgets('at 2 × all steps of a 200 kr fare fit', (tester) async {
      await pump(tester, max: 400);
      for (final step in ['+10 kr', '+20 kr', '+50 kr', '+100 kr']) {
        expect(find.text(step), findsOneWidget, reason: step);
      }
    });

    test('stepsUnder counts to the minor unit (EUR)', () {
      expect(
        PriceBumpCard.stepsUnder(
          const [1, 2, 5],
          currentMinor: 2460,
          maxMinor: 2920,
          currency: 'EUR',
        ),
        [1, 2],
      );
    });
  });
}
