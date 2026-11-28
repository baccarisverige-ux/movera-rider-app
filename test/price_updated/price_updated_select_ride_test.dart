// v0.18.174 (contract.json#priceChangeAsk; owner 2026-11-28 "When price more
// allways show", "No popup, book lower", F1 "Yes, book", FINAL design v8):
// cases 1-4 of the proven "price popup" cases (Rules audits/impact/
// price-updated-popup-2026-11-28.md), driven on the real SelectRide screen
// against a movera-server stand-in (POST /quotes, /trips), in French, first
// price 79,30 €. Any rise opens the shared v8 PriceUpdatedDialog naming the
// ride; a drop books silently at the lower price; ✕ = the old "Pas
// maintenant", the black button = the old "Réserver".
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/theme/app_theme.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/widgets/price_updated_dialog.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/api_reservation_repository.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/application/scheduled_ride_booking.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shots.dart';

const _pickup = LatLng(48.8566, 2.3522);
const _dropoff = LatLng(49.3106, 2.3522);
const first = 7930; // 79,30 €
const drop = 7920; // 79,20 €
const rise = 8150; // 81,50 €
const cent = 7931; // 79,31 € (+1 cent)

/// movera-server stand-in. Every quote costs [price] (EUR) and lives [ttl].
class _Server {
  int price = first;
  Duration ttl = const Duration(minutes: 5);
  final List<Map<String, dynamic>> quoteBodies = [];
  final List<Map<String, dynamic>> tripBodies = [];
  final Map<String, int> _totals = {};
  int _n = 0;

  /// Quotes asked by the reservation repository at booking time (they
  /// carry the payment method), as opposed to list / pin quotes.
  /// v0.18.174: the first POST /trips answers 409 price_changed_ask with
  /// this fresh total (the server booked a higher quote than the agreed).
  int? askFirstTrip;
  final List<Map<String, dynamic>> askedTripBodies = [];

  int get bookingQuotes =>
      quoteBodies.where((b) => b.containsKey('paymentMethod')).length;

  http.Client get client => MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path == '/api/v1/quotes') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      quoteBodies.add(body);
      final wanted =
          (body['categoryIds'] as List?)?.cast<String>() ??
          const ['economy', 'comfort', 'xl'];
      return _json({
        'quotes': [
          for (final category in wanted)
            () {
              final id = 'qte_${++_n}';
              final total = category == 'economy' ? price : price + 3000;
              _totals[id] = total;
              return {
                'quoteId': id,
                'categoryId': category,
                'total': {'amountMinor': total, 'currency': 'EUR'},
                'fareLines': <Object>[],
                'expiresAt': DateTime.now().toUtc().add(ttl).toIso8601String(),
                'pickup': body['pickup'],
                'dropoff': body['dropoff'],
                'stops': body['stops'],
                'pickupAt': body['scheduledAt'],
              };
            }(),
        ],
      });
    }
    if (request.method == 'POST' && path == '/api/v1/trips') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final ask = askFirstTrip;
      if (ask != null) {
        askFirstTrip = null;
        askedTripBodies.add(body);
        return _json({
          'code': 'conflict',
          'message': 'The price went up. Check the new price and book again.',
          'reason': 'price_changed_ask',
          'details': ['fresh:$ask EUR', 'agreed:$first EUR'],
        }, 409);
      }
      tripBodies.add(body);
      return _json({
        'tripId': 'trp_${tripBodies.length}',
        'kind': 'scheduled',
        'status': 'requested',
        'version': 1,
        'categoryId': body['categoryId'],
        'scheduledAt': body['scheduledAt'],
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'pickup': body['pickup'],
        'dropoff': body['dropoff'],
        'stops': body['stops'],
        'fare': {'amountMinor': _totals[body['quoteId']], 'currency': 'EUR'},
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

/// Records the ride-now booking and stops there (Finding is not under test).
class _Booking extends BookingController {
  int submits = 0;
  double? price;
  int? quoteTotalMinor;
  String? quoteId;
  // v0.18.174: what each booking said about the agreed price.
  final List<String?> agreedQuoteIds = [];
  final List<bool> pricesAccepted = [];

  /// The first booking answers 409 price_changed_ask with this total.
  int? askFirst;

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
    String? agreedQuoteId,
    bool priceAccepted = false,
  }) async {
    agreedQuoteIds.add(agreedQuoteId);
    pricesAccepted.add(priceAccepted);
    final ask = askFirst;
    if (ask != null) {
      askFirst = null;
      throw ApiError(
        code: 'conflict',
        message: 'The price went up.',
        statusCode: 409,
        reason: 'price_changed_ask',
        details: ['fresh:$ask EUR', 'agreed:$first EUR'],
      );
    }
    submits++;
    this.price = price;
    this.quoteTotalMinor = quoteTotalMinor;
    this.quoteId = quoteId;
    throw StateError('stop here');
  }
}

const _staging = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.example.test',
);

final _dialog = find.byKey(const ValueKey('select-ride-price-updated'));
final _accept = find.byKey(const ValueKey('select-ride-price-accept'));
final _close = find.byKey(const ValueKey('select-ride-price-close'));

Future<void> settle(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Real seconds pass (quote expiry is judged on the wall clock).
Future<void> wait(WidgetTester tester, int seconds) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(seconds: seconds)));
  await settle(tester, 3);
}

String eur(int minor) => formatMoney(Money(minor, 'EUR'));

DateTime tomorrow() => StockholmSchedule.clampPickup(
  StockholmSchedule.stockholmNow().add(const Duration(days: 1)),
);

class _App {
  _App(this.selection, this.reservations, this.booking);
  final RideSelectionController selection;
  final ReservationController reservations;
  final _Booking booking;
}

Future<_App> _pumpSelect(
  WidgetTester tester,
  _Server server, {
  DateTime? scheduledFor,
  ReservationController? reservations,
  String? editingReservationId,
  bool pickupConfirmed = false,
}) async {
  final api = ApiClient(client: server.client, env: _staging);
  final selection = RideSelectionController(
    catalog: RideCatalogController(api: api, cache: MemoryRideCatalogCache()),
    quotes: ApiQuoteRepository(api: api),
    flags: FeatureFlags(),
  );
  addTearDown(selection.dispose);
  final res =
      reservations ??
      ReservationController(store: ApiReservationRepository(api: api));
  final booking = _Booking();
  phone(tester);
  await tester.pumpWidget(
    framed(
      MaterialApp(
        locale: const Locale(testLang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        theme: moveraTheme(),
        home: SelectRide(
          pickupAddress: 'Rue de Rivoli 1, Paris',
          pickupAlreadyConfirmed: pickupConfirmed,
          destinationAddress: 'Compiègne, Place du Palais',
          pickupPosition: _pickup,
          destinationPosition: _dropoff,
          selection: selection,
          reservations: res,
          booking: booking,
          initialScheduledFor: scheduledFor,
          editingReservationId: editingReservationId,
        ),
      ),
    ),
  );
  await settle(tester, 15);
  return _App(selection, res, booking);
}

Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

/// The v8 popup: one PriceUpdatedDialog, title + grey line, the price ONLY in
/// the black button naming the ride, no old price.
void expectPopup(int was, int now, {String category = 'Movera'}) {
  expect(find.byType(PriceUpdatedDialog), findsOneWidget);
  expect(_dialog, findsOneWidget);
  Finder inDialog(Finder f) => find.descendant(of: _dialog, matching: f);
  expect(
    inDialog(find.text(L10n.current.priceRecalculatedTitle)),
    findsOneWidget,
  );
  expect(
    inDialog(find.text(L10n.current.priceUpdatedRecalculated)),
    findsOneWidget,
  );
  expect(
    inDialog(find.text(L10n.current.bookCategoryForPrice(category, eur(now)))),
    findsOneWidget,
  );
  expect(inDialog(find.textContaining(eur(was))), findsNothing);
  expect(_close, findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    L10n.use(testLang);
    await loadFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    useBlankMaps();
  });

  // ---------------------------------------------------------------- case 1
  // Book now -> Set pickup -> the quote runs out while Set pickup is open
  // -> Confirm: priced again (select_ride_book_now.dart).
  Future<(_App, _Server)> case1(WidgetTester tester, int fresh) async {
    final server = _Server()..ttl = const Duration(seconds: 13);
    final app = await _pumpSelect(tester, server);
    expect(find.text(eur(first)), findsWidgets);
    await tester.tap(find.text(L10n.current.ctaSelect('Movera')));
    await settle(tester, 30);
    expect(find.byKey(const ValueKey('set-pickup-confirm')), findsOneWidget);
    server.ttl = const Duration(minutes: 5);
    server.price = fresh;
    await wait(tester, 14); // the quote runs out on Set pickup
    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    await settle(tester, 60);
    return (app, server);
  }

  for (final fresh in [rise, cent]) {
    testWidgets('case1 Book now: a rise to ${eur(fresh)} opens the v8 popup; '
        'the button books the new price', (tester) async {
      final (app, _) = await case1(tester, fresh);
      expectPopup(first, fresh);
      expect(app.booking.submits, 0);
      await shot(tester, 'case1-book-now-$fresh');
      await tester.tap(_accept);
      await settle(tester, 60);
      expect(app.booking.submits, 1);
      expect(app.booking.quoteTotalMinor, fresh);
      // v0.18.174: the booking names the quote shown in the popup and says
      // the rider accepted its higher price.
      expect(app.booking.agreedQuoteIds.last, app.booking.quoteId);
      expect(app.booking.agreedQuoteIds.last, isNotNull);
      expect(app.booking.pricesAccepted.last, isTrue);
      await close(tester);
    });
  }
  testWidgets('case1 Book now: ✕ books nothing, back on Choose your ride '
      'with the new price; the next tap books it with no second popup (F1)', (
    tester,
  ) async {
    final (app, _) = await case1(tester, rise);
    expectPopup(first, rise);
    await tester.tap(_close);
    await settle(tester, 60);
    expect(_dialog, findsNothing);
    expect(app.booking.submits, 0);
    expect(find.byKey(const ValueKey('set-pickup-confirm')), findsNothing);
    expect(find.text(L10n.current.ctaSelect('Movera')), findsOneWidget);
    expect(find.text(eur(rise)), findsWidgets);
    await close(tester);
  });
  testWidgets('case1 Book now: a drop to 79,20 € books silently at 79,20 €', (
    tester,
  ) async {
    final (app, _) = await case1(tester, drop);
    expect(find.byType(PriceUpdatedDialog), findsNothing);
    expect(app.booking.submits, 1);
    expect(app.booking.quoteTotalMinor, drop);
    // v0.18.174: the agreed quote travels; nothing was accepted.
    expect(app.booking.agreedQuoteIds.single, app.booking.quoteId);
    expect(app.booking.pricesAccepted.single, isFalse);
    await close(tester);
  });
  testWidgets('case1 control: the same price books with no popup', (
    tester,
  ) async {
    final (app, _) = await case1(tester, first);
    expect(find.byType(PriceUpdatedDialog), findsNothing);
    expect(app.booking.submits, 1);
    expect(app.booking.quoteTotalMinor, first);
    await close(tester);
  });
  testWidgets('case1 non-blocking: a second rise while the popup is open '
      'shows the NEWEST price in one popup; nothing is booked at a price '
      'the rider did not see', (tester) async {
    final (app, server) = await case1(tester, rise);
    expectPopup(first, rise);
    server.price = 8200; // the price moves again while the popup is open
    await wait(tester, 21); // past the quote cache's batch reuse
    await tester.tap(_accept);
    await settle(tester, 60);
    if (app.booking.submits == 0) {
      // Asked again: one popup only, with the newest price.
      expect(find.byType(PriceUpdatedDialog), findsOneWidget);
      expectPopup(rise, 8200);
      await tester.tap(_accept);
      await settle(tester, 60);
    }
    expect(find.byType(PriceUpdatedDialog), findsNothing);
    expect(app.booking.submits, 1);
    // Booked only at a price the rider saw in the popup.
    expect([rise, 8200], contains(app.booking.quoteTotalMinor));
    await close(tester);
  });

  // ---------------------------------------------------------------- case 2
  // Book for later -> Set pickup -> the quote runs out -> "Confirmer et
  // programmer": priced again (select_ride_book_scheduled.dart, first check).
  Future<(_App, _Server)> case2(WidgetTester tester, int fresh) async {
    final server = _Server()..ttl = const Duration(seconds: 13);
    final app = await _pumpSelect(tester, server, scheduledFor: tomorrow());
    await tester.tap(find.text(L10n.current.ctaSchedule('Movera')));
    await settle(tester, 30);
    expect(find.text(L10n.current.confirmAndSchedule), findsOneWidget);
    server.ttl = const Duration(minutes: 5);
    server.price = fresh;
    await wait(tester, 14);
    await tester.tap(find.text(L10n.current.confirmAndSchedule));
    await settle(tester, 60);
    return (app, server);
  }

  for (final fresh in [rise, cent]) {
    testWidgets('case2 Schedule: a rise to ${eur(fresh)} opens the v8 popup '
        'before any booking quote; the button books it', (tester) async {
      final (app, server) = await case2(tester, fresh);
      expectPopup(first, fresh);
      expect(server.bookingQuotes, 0);
      await tester.tap(_accept);
      await settle(tester, 60);
      expect(server.tripBodies, hasLength(1));
      expect(app.reservations.all.single.price, fresh / 100);
      await close(tester);
    });
  }
  testWidgets('case2 Schedule: ✕ books nothing (0 POST /trips)', (
    tester,
  ) async {
    final (app, server) = await case2(tester, rise);
    expectPopup(first, rise);
    await tester.tap(_close);
    await settle(tester, 60);
    expect(server.tripBodies, isEmpty);
    expect(app.reservations.all, isEmpty);
    expect(find.text(L10n.current.ctaSchedule('Movera')), findsOneWidget);
    expect(find.text(eur(rise)), findsWidgets);
    await close(tester);
  });
  testWidgets('case2 Schedule: a drop books silently at 79,20 €', (
    tester,
  ) async {
    final (app, server) = await case2(tester, drop);
    expect(find.byType(PriceUpdatedDialog), findsNothing);
    expect(server.tripBodies, hasLength(1));
    expect(app.reservations.all.single.price, drop / 100);
    await close(tester);
  });

  // ---------------------------------------------------------------- case 3
  // Book for later; the server's booking-time quote is another price
  // (ScheduledQuoteRequiredException) -> priced again
  // (select_ride_book_scheduled.dart, R2 retry).
  Future<(_App, _Server)> case3(WidgetTester tester, int fresh) async {
    final server = _Server();
    final app = await _pumpSelect(tester, server, scheduledFor: tomorrow());
    await tester.tap(find.text(L10n.current.ctaSchedule('Movera')));
    await settle(tester, 30);
    server.price = fresh; // the server's price moves while Set pickup is open
    await tester.tap(find.text(L10n.current.confirmAndSchedule));
    await settle(tester, 60);
    return (app, server);
  }

  for (final fresh in [rise, cent]) {
    testWidgets('case3 ScheduledQuoteRequired: a rise to ${eur(fresh)} opens '
        'the v8 popup; the button books it', (tester) async {
      final (app, server) = await case3(tester, fresh);
      expectPopup(first, fresh);
      expect(server.bookingQuotes, 1);
      expect(server.tripBodies, isEmpty);
      await tester.tap(_accept);
      await settle(tester, 60);
      expect(server.tripBodies, hasLength(1));
      expect(app.reservations.all.single.price, fresh / 100);
      await close(tester);
    });
  }
  testWidgets('case3: ✕ books nothing, the list shows the new price', (
    tester,
  ) async {
    final (app, server) = await case3(tester, rise);
    expectPopup(first, rise);
    await tester.tap(_close);
    await settle(tester, 60);
    expect(server.tripBodies, isEmpty);
    expect(app.reservations.all, isEmpty);
    expect(find.text(eur(rise)), findsWidgets);
    await close(tester);
  });
  testWidgets('case3: a drop books silently at 79,20 €', (tester) async {
    final (app, server) = await case3(tester, drop);
    expect(find.byType(PriceUpdatedDialog), findsNothing);
    expect(server.tripBodies, hasLength(1));
    expect(app.reservations.all.single.price, drop / 100);
    await close(tester);
  });

  // ---------------------------------------------------------------- case 4
  // Edit a booked ride -> Review changes -> the quote runs out ->
  // "Confirmer les modifications": priced again
  // (select_ride_booking_helpers.dart _requoteReviewed).
  Future<(_App, _Server, Reservation)> case4(
    WidgetTester tester,
    int fresh,
  ) async {
    final reservations = ReservationController(
      store: LocalReservationRepository(storage: MemoryReservationStorage()),
    );
    final when = tomorrow();
    final seed = RideSelectionController(bookingMode: BookingMode.scheduled);
    addTearDown(seed.dispose);
    final ride = seed.rideById('economy');
    seed.selectRide(ride.id, ride.price);
    seed.scheduleFor(when);
    seed.adoptQuote(
      'economy',
      RideQuote(
        id: 'q_seed',
        rideType: 'economy',
        totalMinor: first,
        currency: 'EUR',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        signedPayload: 'seed',
      ),
    );
    final booked = (await tester.runAsync(
      () => ScheduledRideBooking.confirm(
        reservations: reservations,
        selection: seed,
        pickup: ReservationPlace(
          label: 'Rue de Rivoli 1, Paris',
          lat: _pickup.latitude,
          lng: _pickup.longitude,
        ),
        destination: ReservationPlace(
          label: 'Compiègne, Place du Palais',
          lat: _dropoff.latitude,
          lng: _dropoff.longitude,
        ),
        price: first / 100,
      ),
    ))!;
    final server = _Server()..ttl = const Duration(seconds: 13);
    final app = await _pumpSelect(
      tester,
      server,
      scheduledFor: when.add(const Duration(hours: 1)),
      reservations: reservations,
      editingReservationId: booked.reservationId,
      pickupConfirmed: true,
    );
    await tester.tap(find.text(L10n.current.ctaSchedule('Movera')));
    await settle(tester, 30);
    expect(find.text(L10n.current.resConfirmChanges), findsOneWidget);
    server.ttl = const Duration(minutes: 5);
    server.price = fresh;
    await wait(tester, 14);
    await tester.tap(find.text(L10n.current.resConfirmChanges));
    await settle(tester, 60);
    return (app, server, booked);
  }

  for (final fresh in [rise, cent]) {
    testWidgets('case4 Review changes: a rise to ${eur(fresh)} opens the v8 '
        'popup; the button saves the change at it', (tester) async {
      final (app, _, booked) = await case4(tester, fresh);
      expectPopup(first, fresh);
      await tester.tap(_accept);
      await settle(tester, 60);
      expect(app.reservations.byId(booked.reservationId)!.price, fresh / 100);
      await close(tester);
    });
  }
  testWidgets('case4: ✕ saves nothing (old price and time kept)', (
    tester,
  ) async {
    final (app, _, booked) = await case4(tester, rise);
    expectPopup(first, rise);
    await tester.tap(_close);
    await settle(tester, 60);
    final kept = app.reservations.byId(booked.reservationId)!;
    expect(kept.price, first / 100);
    expect(kept.scheduledPickupAt, booked.scheduledPickupAt);
    await close(tester);
  });
  testWidgets('case4: a drop saves the change silently at 79,20 €', (
    tester,
  ) async {
    final (app, _, booked) = await case4(tester, drop);
    expect(find.byType(PriceUpdatedDialog), findsNothing);
    expect(app.reservations.byId(booked.reservationId)!.price, drop / 100);
    await close(tester);
  });

  // ------------------------------------------------- v0.18.174 409 handling
  testWidgets('case1: a 409 price_changed_ask opens the v8 popup with the '
      "server's fresh price; yes sends it again with priceAccepted", (
    tester,
  ) async {
    final server = _Server();
    final app = await _pumpSelect(tester, server);
    app.booking.askFirst = 8200;
    await tester.tap(find.text(L10n.current.ctaSelect('Movera')));
    await settle(tester, 30);
    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    await settle(tester, 60);
    // Same price at Confirm: no popup before booking; the server asks.
    expect(app.booking.pricesAccepted, [false]);
    expect(app.booking.agreedQuoteIds.single, isNotNull);
    expectPopup(first, 8200);
    await tester.tap(_accept);
    await settle(tester, 60);
    expect(app.booking.pricesAccepted, [false, true]);
    expect(app.booking.submits, 1);
    await close(tester);
  });

  testWidgets('case1: ✕ on the 409 popup books nothing', (tester) async {
    final server = _Server();
    final app = await _pumpSelect(tester, server);
    app.booking.askFirst = 8200;
    await tester.tap(find.text(L10n.current.ctaSelect('Movera')));
    await settle(tester, 30);
    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    await settle(tester, 60);
    expectPopup(first, 8200);
    await tester.tap(_close);
    await settle(tester, 60);
    expect(app.booking.submits, 0);
    expect(app.booking.pricesAccepted, [false]);
    expect(find.byType(PriceUpdatedDialog), findsNothing);
    await close(tester);
  });

  testWidgets('case2: POST /trips carries agreedQuoteId; after a rise is '
      'accepted it carries priceAccepted true', (tester) async {
    final (_, server) = await case2(tester, rise);
    expectPopup(first, rise);
    await tester.tap(_accept);
    await settle(tester, 60);
    final body = server.tripBodies.single;
    expect(body['agreedQuoteId'], isA<String>());
    expect(body['priceAccepted'], isTrue);
    expect(body.keys, isNot(contains('total')));
    await close(tester);
  });

  testWidgets('case2: a drop books with agreedQuoteId and no priceAccepted', (
    tester,
  ) async {
    final (_, server) = await case2(tester, drop);
    final body = server.tripBodies.single;
    expect(body['agreedQuoteId'], isA<String>());
    expect(body.containsKey('priceAccepted'), isFalse);
    await close(tester);
  });

  testWidgets('case2: a 409 price_changed_ask from POST /trips opens the v8 '
      "popup with the server's fresh price; yes books with priceAccepted", (
    tester,
  ) async {
    final server = _Server();
    final app = await _pumpSelect(tester, server, scheduledFor: tomorrow());
    server.askFirstTrip = 8200;
    await tester.tap(find.text(L10n.current.ctaSchedule('Movera')));
    await settle(tester, 30);
    await tester.tap(find.text(L10n.current.confirmAndSchedule));
    await settle(tester, 60);
    expect(server.askedTripBodies.single['agreedQuoteId'], isA<String>());
    expect(server.askedTripBodies.single.containsKey('priceAccepted'), isFalse);
    expectPopup(first, 8200);
    expect(server.tripBodies, isEmpty);
    await tester.tap(_accept);
    await settle(tester, 60);
    expect(server.tripBodies, hasLength(1));
    expect(server.tripBodies.single['priceAccepted'], isTrue);
    expect(app.reservations.all, hasLength(1));
    await close(tester);
  });
}
