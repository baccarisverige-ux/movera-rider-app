import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/mock_catalog_fares.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_projection.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Q7 (owner decision): "Localisation decide currency". The pickup decides
/// the zone and the zone decides the currency: Sweden Z001 kronor, France
/// FR-PC euros, Tunisia TN-TC dinars (three decimals). Every price from the
/// quote to the receipt is in that currency; a kronor wallet never pays a
/// trip in another one; Swedish prices read exactly as before.

typedef _Market = ({
  String name,
  String currency,
  String zoneId,
  double pickupLat,
  double pickupLng,
  double destinationLat,
  double destinationLng,
  String symbol,
});

const _stockholm = (
  name: 'Stockholm',
  currency: 'SEK',
  zoneId: 'Z001',
  pickupLat: 59.3293,
  pickupLng: 18.0686,
  destinationLat: 59.40,
  destinationLng: 18.10,
  symbol: 'kr',
);
const _paris = (
  name: 'Paris',
  currency: 'EUR',
  zoneId: 'FR-PC',
  pickupLat: 48.8606,
  pickupLng: 2.3376,
  destinationLat: 48.8809,
  destinationLng: 2.3553,
  symbol: '€',
);
const _tunis = (
  name: 'Tunis',
  currency: 'TND',
  zoneId: 'TN-TC',
  pickupLat: 36.8008,
  pickupLng: 10.1865,
  destinationLat: 36.8350,
  destinationLng: 10.2350,
  symbol: 'DT',
);

/// Route changes here name their points: nothing is looked up.
class _NoGeo implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

/// Captures what Select Ride books.
class _CaptureBooking extends BookingController {
  double? price;
  int? quoteTotalMinor;
  String? quoteCurrency;
  int? walletAmountMinor;
  int submits = 0;

  @override
  Future<String> submitFinding({
    required String pickupAddress,
    required String destinationAddress,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    required String rideType,
    required double price,
    required String paymentMethod,
    String? quoteId,
    String? quoteSignedPayload,
    DateTime? quoteExpiresAt,
    int? quoteTotalMinor,
    String quoteCurrency = 'SEK',
    String? rideTypeLabel,
    String? paymentMethodLabel,
    RideNotes notes = RideNotes.empty,
    List<RouteStop> stops = const <RouteStop>[],
    bool useWalletFirst = false,
    int walletAmountMinor = 0,
  }) async {
    submits++;
    this.price = price;
    this.quoteTotalMinor = quoteTotalMinor;
    this.quoteCurrency = quoteCurrency;
    this.walletAmountMinor = walletAmountMinor;
    throw StateError('stop here');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late InProcessMockClient server;
  late ApiClient api;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    LastCompletedRide.clear();
    AppScope.instance.ride.restoreFromBackend(RideStatus.idle);
    AppScope.instance.ride.rideId = null;
    now = DateTime.now();
    server = InProcessMockClient(clock: () => now);
    api = ApiClient(client: server);
  });

  Future<RideQuote> quoteIn(_Market market, {String category = 'economy'}) =>
      ApiQuoteRepository(api: api).quote(
        rideType: category,
        distanceMeters: 3000,
        pickup: 'Pickup',
        destination: 'Destination',
        pickupPoint: GeoPoint(market.pickupLat, market.pickupLng),
        destinationPoint: GeoPoint(
          market.destinationLat,
          market.destinationLng,
        ),
      );

  Future<String> bookIn(_Market market, RideQuote quote) =>
      BookingCoordinator(api: api).submitFinding(
        pickupAddress: 'Pickup',
        destinationAddress: 'Destination',
        pickupLat: market.pickupLat,
        pickupLng: market.pickupLng,
        destinationLat: market.destinationLat,
        destinationLng: market.destinationLng,
        rideType: quote.rideType,
        price: Money(quote.totalMinor, quote.currency).major,
        paymentMethod: 'card',
        paymentMethodLabel: 'Visa •••• 4242',
        quoteId: quote.id,
        quoteSignedPayload: quote.signedPayload,
        quoteExpiresAt: quote.expiresAt,
        quoteTotalMinor: quote.totalMinor,
        quoteCurrency: quote.currency,
      );

  Future<Map<String, dynamic>> simulate(
    String id,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    (await api.post('/api/v1/rides/$id/status', body: body))['ride'] as Map,
  );

  Future<ApiError> refused(Future<Object?> call) async {
    try {
      await call;
    } on ApiError catch (error) {
      return error;
    }
    fail('expected an ApiError');
  }

  group('one money format per currency', () {
    test('Swedish prices read exactly as before', () {
      expect(formatSek(10200), '102 kr');
      expect(formatSek(10250), '103 kr');
      expect(formatKr(522.0), '522 kr');
      expect(formatKr(100.4), '100 kr');
      expect(formatKr(-25), '-25 kr');
      expect(formatMoney(const Money(3500)), '35 kr');
      expect(formatMoney(const Money(3550)), '35,50 kr'); // rider-r4-16
      expect(formatMoney(const Money(7410), whole: true), '74 kr');
    });

    test('euros and dinars in their own format, to the minor unit', () {
      expect(formatMoney(const Money(741, 'EUR')), '7,41 €');
      expect(formatMoney(const Money(700, 'EUR'), whole: true), '7,00 €');
      expect(formatMoney(const Money(7410, 'TND')), '7,410 DT');
      expect(formatMoney(const Money(19500, 'TND'), whole: true), '19,500 DT');
      expect(formatMajor(5, 'EUR'), '5,00 €');
    });
  });

  group('the pickup decides the zone, the zone the currency', () {
    test('Stockholm, Paris and Tunis; anywhere else is the home zone', () {
      for (final market in [_stockholm, _paris, _tunis]) {
        final zone = RiderZones.at(market.pickupLat, market.pickupLng);
        expect(zone.id, market.zoneId, reason: market.name);
        expect(zone.currency, market.currency, reason: market.name);
      }
      expect(RiderZones.at(40.71, -74.0).id, 'Z001');
      expect(RiderZones.at(null, null).id, 'Z001');
    });

    test('each zone has its config document, with its own fees', () async {
      const repository = SeedRiderConfigRepository();
      for (final market in [_stockholm, _paris, _tunis]) {
        final config = await repository.forZone(market.zoneId);
        expect(config.zoneId, market.zoneId);
        expect(config.currency, market.currency);
        final premium = config.liveFeeFor('premium')!;
        expect(premium.min!.currency, market.currency);
      }
      // The Paris and Tunis seeds are Admin's export (same fees, waiting).
      for (final market in [_paris, _tunis]) {
        final fixture = RiderAppConfig.fromJson(
          jsonDecode(
            await File(
              'test/fixtures/admin_config/rider_app_config.${market.zoneId}.json',
            ).readAsString(),
          ),
        )!;
        final seed = SeedRiderConfigRepository.seedFor(market.zoneId);
        for (final category in ['economy', 'comfort', 'premium', 'xl']) {
          expect(
            seed.liveFeeFor(category)?.toJson(),
            fixture.liveFeeFor(category)?.toJson(),
            reason: '${market.zoneId} $category live',
          );
          expect(
            seed.reservationFeeFor(category)?.toJson(),
            fixture.reservationFeeFor(category)?.toJson(),
            reason: '${market.zoneId} $category reservation',
          );
        }
        expect(seed.waiting!.noShowFee, fixture.waiting!.noShowFee);
        expect(seed.waiting!.perMin, fixture.waiting!.perMin);
      }
    });
  });

  for (final market in [_tunis, _paris]) {
    group('${market.currency}: book → trip → receipt (${market.name})', () {
      test('the quote, the booking, the offer and the route change', () async {
        final quote = await quoteIn(market);
        expect(quote.currency, market.currency);
        final step = MockZoneCurrency.of(market.currency).stepMinor;
        expect(quote.totalMinor % step, 0, reason: 'on the zone price step');
        // The zone's own price, not a kronor amount read as dinars or euros.
        final list = MockZoneRates(
          catalogKronor: mockCatalogPricesKr['economy']!,
          currency: market.currency,
        );
        expect(quote.totalMinor, greaterThanOrEqualTo(list.listMinor * 0.6));
        expect(quote.totalMinor, lessThan(list.listMinor * 3));

        final id = await bookIn(market, quote);
        final ride = server.rides[id]!;
        expect(ride['fare'], {
          'amountMinor': quote.totalMinor,
          'currency': market.currency,
        });
        final saved = (await RideSnapshotStore.read())!;
        expect(saved.currency, market.currency);
        expect(saved.fare, Money(quote.totalMinor, market.currency));
        final unit = Money.minorPerMajor(market.currency);
        expect(saved.maxOfferMinor! % unit, 0, reason: 'a whole-unit ceiling');

        // The offer: raised in the trip's currency, refused in kronor.
        final realtime = MockRideRealtime(
          assignAfter: const Duration(days: 1),
          api: api,
        );
        addTearDown(realtime.dispose);
        final session = RideSession()..rideId = id;
        final finding = FindingDriverController(
          realtime: realtime,
          ride: session,
          store: FindingDriverRepository(),
          priceBumpAfter: Duration.zero,
          api: api,
        );
        addTearDown(finding.dispose);
        finding.start(snapshot: saved, onTick: (_) {}, onMatched: () {});
        expect(finding.currency, market.currency);
        expect(
          await finding.confirmPriceIncreaseBy(const Money(500, 'SEK')),
          isFalse,
        );
        final raise = Money(2 * unit + step, market.currency);
        expect(await finding.confirmPriceIncreaseBy(raise), isTrue);
        final raised = quote.totalMinor + raise.amountMinor;
        expect(server.rides[id]!['fare'], {
          'amountMinor': raised,
          'currency': market.currency,
        });
        expect(
          finding.offerConfirmation,
          'Updated offer: ${formatMoney(Money(raised, market.currency))}',
        );
        expect(finding.offerConfirmation, endsWith(market.symbol));
        final kronorRaise = await refused(
          api.patch(
            '/api/v1/rides/$id',
            body: {'offerIncrease': const Money(5000).toJson()},
          ),
        );
        expect(kronorRaise.statusCode, 422);

        // The route change is priced and applied in the trip's currency.
        final controller = RouteChangeController(api: api, geocoding: _NoGeo());
        final current = (await RideSnapshotStore.read())!;
        final change = await controller.preview(
          ride: current,
          destinationAddress: 'Further away',
          destinationPoint: GeoPoint(
            market.destinationLat + 0.02,
            market.destinationLng + 0.02,
          ),
        );
        expect(change.currency, market.currency);
        expect(change.newTotalMinor! % step, 0);
        expect(change.newPriceKr, greaterThan(change.oldPriceKr));
        final applied = await controller.apply(ride: current, quote: change);
        expect(applied.currency, market.currency);
        expect(server.rides[id]!['fare'], {
          'amountMinor': change.newTotalMinor,
          'currency': market.currency,
        });
        final adjustment =
            (server.rides[id]!['paymentAdjustments'] as List).single as Map;
        expect((adjustment['amount'] as Map)['currency'], market.currency);
      });

      test('the cancel fee is the zone\'s own rule, in its currency', () async {
        final quote = await quoteIn(market);
        final id = await bookIn(market, quote);
        await simulate(id, {'status': 'accepted'});
        now = now.add(const Duration(minutes: 10));
        final cancelled =
            (await api.post(
                  '/api/v1/rides/$id/cancel',
                  body: {'reasonCode': 'plans_changed'},
                ))['ride']
                as Map;
        final fee = Money.fromWire((cancelled['cancellation'] as Map)['fee'])!;
        final rule = SeedRiderConfigRepository.seedFor(
          market.zoneId,
        ).liveFeeFor('economy')!;
        expect(fee, Money(rule.value.toInt(), market.currency));

        // The preview the rider sees before confirming uses the same rule.
        final config = await const SeedRiderConfigRepository().forZone(
          RiderZones.byCurrency(market.currency)!.id,
        );
        final preview = LiveCancelFeePreview.of(
          config,
          categoryId: 'economy',
          fare: Money(quote.totalMinor, market.currency),
          acceptedAt: now.subtract(const Duration(minutes: 10)),
          now: now,
        )!;
        expect(preview.fee, fee);
        expect(formatMoney(preview.fee), endsWith(market.symbol));
      });

      test('Q8: only the wallet of the trip currency pays; kronor never do',
          () async {
        SharedPreferences.setMockInitialValues({
          WalletStore.balanceKey: 500.0,
          WalletStore.balanceKeyFor(market.currency): 100.0,
        });
        final quote = await quoteIn(market);
        final selection = RideSelectionController(
          flags: const FeatureFlags(),
          currency: market.currency,
        )..setWalletBalance(50);
        addTearDown(selection.dispose);
        selection.adoptQuote('economy', quote);
        expect(selection.walletMatchesTrip, isFalse);
        expect(selection.walletSplitFor(quote.totalMinor).usesWallet, isFalse);
        expect(
          selection.payments().map((item) => item.brand),
          isNot(contains('wallet')),
        );

        // The server takes a wallet part in the trip's own currency (Q8:
        // one wallet per currency, no conversion).
        final created = await api.post(
            '/api/v1/rides',
            body: {
              'categoryId': 'economy',
              'fare': Money(quote.totalMinor, quote.currency).toJson(),
              'paymentMethodId': 'card',
              'pickupAddress': 'Pickup',
              'destinationAddress': 'Destination',
              'pickupLat': market.pickupLat,
              'pickupLng': market.pickupLng,
              'destinationLat': market.destinationLat,
              'destinationLng': market.destinationLng,
              'quoteId': quote.id,
              'quoteSignedPayload': quote.signedPayload,
              'quoteExpiresAt': quote.expiresAt.toUtc().toIso8601String(),
              'quoteTotalMinor': quote.totalMinor,
              'useWalletFirst': true,
              'walletAmountMinor': 1000,
            },
        );
        expect(created['ride'], isNotNull);

        // A completed wallet trip is taken off that currency's balance,
        // never off the kronor one.
        final snapshot = RideSnapshot(
          status: RideStatus.paymentFinalized,
          savedAt: DateTime.now(),
          pickupAddress: 'Pickup',
          destinationAddress: 'Destination',
          pickupLat: market.pickupLat,
          pickupLng: market.pickupLng,
          destinationLat: market.destinationLat,
          destinationLng: market.destinationLng,
          rideType: 'Movera',
          price: Money(quote.totalMinor, quote.currency).major,
          currency: quote.currency,
          paymentMethod: 'Movera Wallet',
          paymentMethodId: 'wallet',
          rideId: 'paid-elsewhere',
        );
        final wallet = WalletController();
        final fare = Money(quote.totalMinor, quote.currency);
        expect(
          await wallet.chargeCompletedRide(snapshot, rideId: 'paid-elsewhere'),
          closeTo(100 - fare.major, 1e-6),
        );
        expect(await wallet.loadBalance(), 500.0);
        expect(
          await wallet.forCurrency(market.currency).loadBalance(),
          closeTo(100 - fare.major, 1e-6),
        );
      });

      testWidgets('the receipt, the waybill and History', (tester) async {
        tester.view.physicalSize = const Size(390, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late String id;
        late RideQuote quote;
        late RideSnapshot completed;
        await tester.runAsync(() async {
          quote = await quoteIn(market);
          id = await bookIn(market, quote);
          await simulate(id, {'status': 'completed'});
          final projection = Map<String, dynamic>.from(
            (await api.get('/api/v1/rides/$id'))['ride'] as Map,
          );
          completed = RideProjection.toSnapshot(projection)!;
        });
        expect(completed.currency, market.currency);
        final fare = Money(quote.totalMinor, market.currency);
        final shown = formatMoney(fare, whole: true);
        expect(shown, endsWith(' ${market.symbol}'));
        expect(shown, isNot(contains('kr')));

        LastCompletedRide.remember(completed);
        await tester.pumpWidget(
          MoveraScreenUtilInit(
            builder: (_, __) => MaterialApp(
              home: RideCompleted(
                status: RideStatus.paymentFinalized,
                rideId: id,
                persistOnDemandState: false,
                showConnectionBanner: false,
                controller: RideCompleteController(),
                onClose: (_) async {},
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Booked price'), findsOneWidget);
        expect(find.text(shown), findsOneWidget);
        expect(find.textContaining(' kr'), findsNothing);
        // Tip amounts are kronor: none are offered on this trip.
        expect(find.text('10 kr'), findsNothing);

        final record = OnDemandRideHistoryStore.recordFor(
          completed,
          terminalStatus: RideStatus.paymentFinalized,
        )!;
        expect(record.currency, market.currency);
        expect(ReservationFormat.price(record), shown);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 30));
      });
    });
  }

  group('SEK is unchanged', () {
    test('a Stockholm quote and booking are the kronor formula', () async {
      final quote = await quoteIn(_stockholm);
      expect(quote.currency, 'SEK');
      final id = await bookIn(_stockholm, quote);
      final saved = (await RideSnapshotStore.read())!;
      expect(saved.currency, 'SEK');
      expect(saved.toJson().containsKey('currency'), isFalse);
      expect(server.rides[id]!['fare'], {
        'amountMinor': quote.totalMinor,
        'currency': 'SEK',
      });
      // The same price as the kronor table: whole kronor.
      expect(quote.totalMinor % 100, 0);
      const rates = MockCategoryRates(catalogMajor: 259);
      final zoned = MockZoneRates(catalogKronor: 259, currency: 'SEK');
      for (final meters in [0, 3000, 3125, 8000, 21345]) {
        expect(
          zoned.quote(meters).amountMinor,
          rates.quoteMajor(meters) * 100,
          reason: '$meters m',
        );
        expect(zoned.distanceFare(meters), rates.distanceFare(meters, 'SEK'));
      }
      expect(zoned.baseFare, rates.baseFare('SEK'));
    });

    testWidgets('the offer card reads as before', (tester) async {
      final confirmed = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PriceBumpCard(
                currentPrice: 259,
                maxPrice: 466,
                steps: const [50, 100, 150, 200],
                onConfirm: confirmed.add,
                onKeepWaiting: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Current 259 kr'), findsOneWidget);
      expect(find.text('+50 kr'), findsOneWidget);
      await tester.tap(find.text('+100 kr'));
      await tester.pump();
      expect(find.text('Confirm 359 kr'), findsOneWidget);
    });
  });

  testWidgets('the offer card in euros raises to the cent', (tester) async {
    Money? raised;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PriceBumpCard(
              currentPrice: 24.6,
              maxPrice: 44,
              currency: 'EUR',
              steps: const [],
              onConfirm: (_) => fail('whole units are for kronor'),
              onConfirmIncrease: (increase) => raised = increase,
              onKeepWaiting: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Current 24,60 €'), findsOneWidget);
    expect(find.textContaining('kr'), findsNothing);
    await tester.enterText(find.byType(TextField), '30');
    await tester.pump();
    await tester.tap(find.text('Confirm 30,00 €'));
    expect(raised, const Money(540, 'EUR'));
  });

  testWidgets(
    'Select Ride in Paris: euro prices, the euro wallet first, euro booking',
    (tester) async {
      // Q8: 100,5 kr never pay a euro trip; the 5 € wallet does, first.
      SharedPreferences.setMockInitialValues(<String, Object>{
        WalletStore.balanceKey: 100.5,
        WalletStore.balanceKeyFor('EUR'): 5.0,
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = RideCatalogController(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
          ),
        ),
        cache: MemoryRideCatalogCache(),
      );
      final selection = RideSelectionController(
        catalog: catalog,
        quotes: ApiQuoteRepository(api: api),
      );
      addTearDown(selection.dispose);
      final booking = _CaptureBooking();
      await tester.pumpWidget(
        MaterialApp(
          home: SelectRide(
            pickupAddress: 'Musée du Louvre',
            destinationAddress: 'Gare du Nord',
            pickupPosition: LatLng(_paris.pickupLat, _paris.pickupLng),
            destinationPosition: LatLng(
              _paris.destinationLat,
              _paris.destinationLng,
            ),
            selection: selection,
            booking: booking,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(selection.currency, 'EUR');
      final quote = selection.authoritativeQuotes['economy']!;
      final price = formatMoney(Money(quote.totalMinor, 'EUR'), whole: true);
      expect(find.text(price), findsWidgets);
      expect(find.textContaining(RegExp(r'\d kr\b')), findsNothing);
      expect(
        find.byKey(const ValueKey('select-ride-wallet-line')),
        findsWidgets,
      );
      expect(find.textContaining('Wallet −5,00 €'), findsWidgets);
      expect(
        find.byKey(const ValueKey('select-ride-wallet-currency-note')),
        findsNothing,
      );

      await tester.tap(find.text('Select Movera'));
      for (var i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(SetPickupPage), findsOneWidget);
      expect(
        tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('set-pickup-wallet-part')),
            matching: find.text('-5,00 €'),
          ),
        ),
        isNotNull,
      );
      expect(find.text(price), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(booking.submits, 1);
      expect(booking.quoteCurrency, 'EUR');
      expect(booking.quoteTotalMinor, quote.totalMinor);
      expect(booking.price, Money(quote.totalMinor, 'EUR').major);
      expect(booking.walletAmountMinor, 500);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
    },
  );
}
