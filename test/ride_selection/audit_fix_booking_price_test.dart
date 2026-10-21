import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

/// Prices depend on the pin: a quote from a moved pin costs more. The first
/// quote can be made short-lived to let it expire on Set pickup.
class _Quotes implements QuoteRepository {
  _Quotes({
    this.firstTtl = const Duration(minutes: 5),
    this.baseMinor = 25900,
    this.movedMinor = 30100,
  });

  final Duration firstTtl;
  final int baseMinor;
  final int movedMinor;
  int calls = 0;
  int? first;

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
  }) {
    calls++;
    first ??= distanceMeters;
    final minor = distanceMeters != first ? movedMinor : baseMinor;
    return Future<RideQuote>.value(
      RideQuote(
        id: 'quote-$rideType-$calls',
        rideType: rideType,
        totalMinor: minor,
        currency: 'SEK',
        expiresAt: DateTime.now().add(
          calls == 1 ? firstTtl : const Duration(minutes: 5),
        ),
        signedPayload: 'signature',
      ),
    );
  }
}

/// Like [_Quotes], but the moved pin's quote waits for [pin].
class _SlowPinQuotes extends _Quotes {
  _SlowPinQuotes({super.baseMinor, super.movedMinor});

  Completer<void>? pin;

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
    final answer = await super.quote(
      rideType: rideType,
      distanceMeters: distanceMeters,
      pickup: pickup,
      destination: destination,
    );
    // Only the first quote from the moved pin is slow.
    if (distanceMeters == first || pin != null) return answer;
    final wait = pin = Completer<void>();
    await wait.future;
    return answer;
  }
}

class _CaptureBooking extends BookingController {
  double? price;
  String? quoteId;
  DateTime? quoteExpiresAt;
  bool? useWalletFirst;
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
    this.quoteId = quoteId;
    this.quoteExpiresAt = quoteExpiresAt;
    this.useWalletFirst = useWalletFirst;
    this.walletAmountMinor = walletAmountMinor;
    throw StateError('stop here');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  RideSelectionController selectionWith(QuoteRepository quotes) {
    final catalog = RideCatalogController(
      api: ApiClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
        ),
      ),
      cache: MemoryRideCatalogCache(),
    );
    return RideSelectionController(catalog: catalog, quotes: quotes);
  }

  Future<void> openSetPickup(
    WidgetTester tester,
    RideSelectionController selection,
    _CaptureBooking booking,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.6519, 17.9186),
          selection: selection,
          booking: booking,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Select Movera'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('RIDE-1: Confirm books the fare shown after the pin moved', (
    tester,
  ) async {
    final quotes = _Quotes();
    final selection = selectionWith(quotes);
    final booking = _CaptureBooking();
    await openSetPickup(tester, selection, booking);
    expect(find.text('259 kr'), findsWidgets);

    final map = tester.widget<CustomGoogleMap>(
      find.byKey(const ValueKey('set-pickup-map')),
    );
    map.onCameraMoveStarted!();
    map.onCameraMove!(
      const CameraPosition(target: LatLng(59.31, 18.0686), zoom: 16),
    );
    map.onCameraIdle!();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The re-quote went through the selection's own repository.
    expect(find.text('301 kr'), findsWidgets);
    final pinQuoteId = 'quote-economy-${quotes.calls}';

    await confirm(tester);
    expect(booking.submits, 1);
    expect(booking.price, 301);
    expect(booking.quoteId, pinQuoteId);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
  });

  Future<void> priceLandsAfterConfirm(
    WidgetTester tester,
    _SlowPinQuotes quotes,
    _CaptureBooking booking,
  ) async {
    final selection = selectionWith(quotes);
    await openSetPickup(tester, selection, booking);
    final map = tester.widget<CustomGoogleMap>(
      find.byKey(const ValueKey('set-pickup-map')),
    );
    map.onCameraMoveStarted!();
    map.onCameraMove!(
      const CameraPosition(target: LatLng(59.31, 18.0686), zoom: 16),
    );
    map.onCameraIdle!();
    await tester.pump();
    await confirm(tester);
    quotes.pin!.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('rider-r4-33: "Price updated" shows the öre when the whole '
      'kronor are the same', (tester) async {
    await priceLandsAfterConfirm(
      tester,
      _SlowPinQuotes(baseMinor: 25440, movedMinor: 25420),
      _CaptureBooking(),
    );
    final dialog = find.byKey(const ValueKey('select-ride-price-updated'));
    expect(
      find.descendant(of: dialog, matching: find.textContaining('254,20 kr')),
      findsWidgets,
    );
    expect(
      find.descendant(of: dialog, matching: find.textContaining('254,40 kr')),
      findsOneWidget,
    );
    await tester.tap(find.text('Not now'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
  });

  testWidgets(
    'RIDE-1: a price that lands after Confirm is agreed to before booking',
    (tester) async {
      final quotes = _SlowPinQuotes();
      final selection = selectionWith(quotes);
      final booking = _CaptureBooking();
      await openSetPickup(tester, selection, booking);

      final map = tester.widget<CustomGoogleMap>(
        find.byKey(const ValueKey('set-pickup-map')),
      );
      map.onCameraMoveStarted!();
      map.onCameraMove!(
        const CameraPosition(target: LatLng(59.31, 18.0686), zoom: 16),
      );
      map.onCameraIdle!();
      await tester.pump();
      expect(quotes.pin, isNotNull);

      // Confirm while the pin's price is still loading; Set pickup gives up
      // waiting and closes with the old price shown.
      await confirm(tester);
      expect(find.byType(SetPickupPage), findsNothing);
      expect(booking.submits, 0);

      quotes.pin!.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const ValueKey('select-ride-price-updated')),
        findsOneWidget,
      );
      expect(booking.submits, 0);
      await tester.tap(find.byKey(const ValueKey('select-ride-price-accept')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(booking.submits, 1);
      expect(booking.price, 301);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
    },
  );

  testWidgets(
    'RIDE-2: a quote that runs out on Set pickup is refreshed and booked, '
    'not failed',
    (tester) async {
      // Still bookable when Book is tapped, but it runs out within the
      // moment booking needs once the rider confirms on Set pickup.
      final quotes = _Quotes(firstTtl: const Duration(seconds: 5));
      final selection = selectionWith(quotes);
      final booking = _CaptureBooking();
      await openSetPickup(tester, selection, booking);
      final callsBefore = quotes.calls;

      await confirm(tester);
      expect(quotes.calls, greaterThan(callsBefore));
      expect(booking.submits, 1);
      expect(booking.quoteId, isNot('quote-economy-1'));
      expect(booking.quoteExpiresAt!.isAfter(DateTime.now()), isTrue);
      expect(booking.price, 259);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
    },
  );

  testWidgets(
    'ARCH-5: the wallet part the rider was shown is sent with the booking',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        WalletStore.balanceKey: 100.5,
      });
      final selection = selectionWith(_Quotes());
      final booking = _CaptureBooking();
      await openSetPickup(tester, selection, booking);
      expect(
        find.byKey(const ValueKey('set-pickup-wallet-part')),
        findsOneWidget,
      );

      await confirm(tester);
      expect(booking.submits, 1);
      expect(booking.useWalletFirst, isTrue);
      expect(booking.walletAmountMinor, 10050);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
    },
  );

  group('RIDE-11: pin re-quotes apply in request order', () {
    test('a late answer for an older pin is not adopted', () async {
      final answers = <Completer<RideQuote>>[];
      final selection = RideSelectionController(
        store: RideSelectionRepository(),
        quotes: _ManualQuotes(answers),
        flags: const FeatureFlags(),
      );
      addTearDown(selection.dispose);

      final a = selection.quoteFromPin(rideId: 'economy', distanceMeters: 1);
      final b = selection.quoteFromPin(rideId: 'economy', distanceMeters: 2);
      answers[1].complete(_quote('pin-b', 30100));
      expect(await b, isNotNull);
      answers[0].complete(_quote('pin-a', 28000));
      expect(await a, isNull);
      expect(selection.authoritativeQuotes['economy']!.id, 'pin-b');
      expect(selection.offeredPrices['economy'], 301);
    });

    test(
      'a list load begun before the pin quote cannot overwrite it',
      () async {
        final answers = <Completer<RideQuote>>[];
        final selection = RideSelectionController(
          store: RideSelectionRepository(),
          quotes: _ManualQuotes(answers),
          flags: const FeatureFlags(),
        );
        addTearDown(selection.dispose);

        final load = selection.loadQuotes(
          generation: selection.beginQuotes(),
          pickup: 'old point',
          destination: 'Arlanda',
          parallelism: 100,
        );
        final listCount = answers.length;
        final pin = selection.quoteFromPin(rideId: 'economy', distanceMeters: 2);
        answers.last.complete(_quote('pin', 30100));
        await pin;
        for (var i = 0; i < listCount; i++) {
          answers[i].complete(_quote('old-$i', 25900));
        }
        await load;
        expect(selection.authoritativeQuotes['economy']!.id, 'pin');
      },
    );
  });
}

RideQuote _quote(String id, int minor) => RideQuote(
  id: id,
  rideType: 'economy',
  totalMinor: minor,
  currency: 'SEK',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  signedPayload: 'signature',
);

class _ManualQuotes implements QuoteRepository {
  _ManualQuotes(this.answers);

  final List<Completer<RideQuote>> answers;

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
  }) {
    final c = Completer<RideQuote>();
    answers.add(c);
    return c.future.then(
      (q) => RideQuote(
        id: q.id,
        rideType: rideType,
        totalMinor: q.totalMinor,
        currency: q.currency,
        expiresAt: q.expiresAt,
        signedPayload: q.signedPayload,
      ),
    );
  }
}
