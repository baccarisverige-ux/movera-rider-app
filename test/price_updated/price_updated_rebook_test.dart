// v0.18.174 (contract.json#priceChangeAsk; owner 2026-11-28, FINAL design
// v8): cases 5-6 of the proven price popup cases (rebook_price_dialog.dart),
// driven on the real Finding drivers and Waiting for driver screens, in
// French. Any rise opens the shared v8 PriceUpdatedDialog naming the ride
// ("Réserver Movera · 81,50 €"); a drop starts the new search silently at the
// lower price; ✕ = the old "Pas maintenant".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/app/theme/app_theme.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/booking/application/booking_controller.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/booking/data/booking_repository.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/presentation/finding_drivers.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shots.dart';

const _pickup = LatLng(48.8566, 2.3522);
// The in-process server prices economy from the route: these two drop-offs
// cost exactly 79,20 € and 81,50 € (searched once, deterministic).
const _dropFor = {7920: LatLng(49.3106, 2.3522), 8150: LatLng(49.3286, 2.3522)};
const first = 7930;
const drop = 7920;
const rise = 8150;
// +1 cent: the in-process server prices in 10-cent steps, so the ride first
// shown at 79,19 € is priced again at 79,20 € (the 79,20 € drop-off).
const centFirst = 7919;
const cent = 7920;

String eur(int minor) => formatMoney(Money(minor, 'EUR'));

final _dialog = find.byKey(const ValueKey('rebook-price-updated'));
final _accept = find.byKey(const ValueKey('rebook-price-accept'));
final _close = find.byKey(const ValueKey('rebook-price-close'));

/// The v8 popup naming the ride, the new price only in the button.
void expectPopup(int was, int now) {
  expect(find.byType(PriceUpdatedDialog), findsOneWidget);
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
    inDialog(find.text(L10n.current.bookCategoryForPrice('Movera', eur(now)))),
    findsOneWidget,
  );
  expect(inDialog(find.textContaining(eur(was))), findsNothing);
  expect(_close, findsOneWidget);
}

class _Backend extends http.BaseClient {
  _Backend(this.inner);
  final InProcessMockClient inner;
  final List<String> rideBookings = [];
  final List<int> quoteTotals = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' && request.url.path == '/api/v1/rides') {
      rideBookings.add(request.url.path);
    }
    return inner.send(request);
  }
}

Widget _app(GlobalKey<NavigatorState> nav, String home) => framed(
  ScreenUtilInit(
    designSize: const Size(393, 852),
    minTextAdapt: true,
    splitScreenMode: true,
    builder: (_, __) => MaterialApp(
      navigatorKey: nav,
      locale: const Locale(testLang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      theme: moveraTheme(),
      home: Scaffold(body: Center(child: Text(home))),
    ),
  ),
);

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int max = 120,
}) async {
  for (var i = 0; i < max && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    useBlankMaps();
  });

  void resetSession() {
    RideRestoreCoordinator.instance.showing = RestoredSurface.home;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..bookedCategoryId = null
      ..bookedPaymentMethodId = null;
  }

  // ---------------------------------------------------------------- case 5
  // A ride now searched at 79,30 €; the server ends the search with no
  // driver -> "Aucun chauffeur trouvé" -> "Relancer la recherche": the route
  // is priced again (finding_drivers.dart:644 via _requestAgain).
  group('case5 Finding drivers: No driver found -> Relancer la recherche', () {
    late InProcessMockClient server;
    late _Backend backend;
    late MockRideRealtime realtime;

    Future<FindingDriverController> noDriverFound(
      WidgetTester tester,
      int fresh, {
      int shown = first,
    }) async {
      phone(tester);
      server = InProcessMockClient(searchExpiresAfter: Duration.zero);
      backend = _Backend(server);
      final api = ApiClient(client: backend);
      realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        api: api,
      );
      addTearDown(realtime.dispose);
      resetSession();
      const id = 'proof-no-driver';
      server.rides[id] = {
        'id': id,
        'status': 'findingDriver',
        'version': 1,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'searchStartedAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 4))
            .toIso8601String(),
        'categoryId': 'economy',
        'paymentMethodId': 'cash',
      };
      AppScope.instance.ride
        ..rideId = id
        ..status = RideStatus.findingDriver
        ..authoritativeVersion = 1
        ..bookedCategoryId = 'economy'
        ..bookedPaymentMethodId = 'cash';
      final controller = FindingDriverController(realtime: realtime, api: api);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(_app(nav, 'accueil'));
      nav.currentState!.push(
        RideStageTransition(
          FindingDrivers(
            pickupAddress: 'Rue de Rivoli 1, Paris',
            destinationAddress: 'Compiègne, Place du Palais',
            pickupPosition: _pickup,
            destinationPosition: _dropFor[fresh] ?? _dropFor[drop]!,
            rideType: 'Movera',
            price: shown / 100,
            currency: 'EUR',
            paymentMethod: 'Payer à bord',
            realtime: realtime,
            searchStartedAt: DateTime.now(),
            controller: controller,
            booking: BookingController(
              store: BookingRepository(
                coordinator: BookingCoordinator(api: api),
              ),
            ),
          ),
          settings: const RouteSettings(name: AppRoutes.findingDriver),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      unawaited(controller.checkServerSearchState());
      await pumpUntil(
        tester,
        () => find.text(L10n.current.searchAgain).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(L10n.current.searchAgain), findsOneWidget);
      server.rides.clear();
      await tester.tap(find.text(L10n.current.searchAgain));
      await pumpUntil(
        tester,
        () => _dialog.evaluate().isNotEmpty || backend.rideBookings.isNotEmpty,
      );
      return controller;
    }

    /// The fare the new ride was booked at (the in-process server's row).
    int? bookedMinor(String? id) =>
        ((server.rides[id]?['fare'] as Map?)?['amountMinor'] as num?)?.round();

    for (final (shown, fresh) in [(first, rise), (centFirst, cent)]) {
      testWidgets('case5: a rise ${eur(shown)} -> ${eur(fresh)} opens the v8 '
          'popup; the button books a new search at it', (tester) async {
        await noDriverFound(tester, fresh, shown: shown);
        expectPopup(shown, fresh);
        expect(backend.rideBookings, isEmpty);
        await shot(tester, 'case5-no-driver-found-$fresh');
        await tester.tap(_accept);
        await pumpUntil(tester, () => backend.rideBookings.isNotEmpty);
        await tester.pump(const Duration(milliseconds: 400));
        expect(backend.rideBookings, hasLength(1));
        final newId = AppScope.instance.ride.rideId;
        expect(newId, isNot('proof-no-driver'));
        expect(find.byType(FindingDrivers), findsOneWidget);
        expect(bookedMinor(newId), fresh);
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets('case5: ✕ books nothing (0 POST /rides), stays on No driver '
        'found', (tester) async {
      await noDriverFound(tester, rise);
      expectPopup(first, rise);
      await tester.tap(_close);
      await pumpUntil(
        tester,
        () => find.text(L10n.current.searchAgain).evaluate().isNotEmpty,
      );
      expect(_dialog, findsNothing);
      expect(backend.rideBookings, isEmpty);
      expect(find.text(L10n.current.searchAgain), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('case5: a drop 79,30 -> 79,20 € opens no popup and starts the '
        'new search at 79,20 €', (tester) async {
      await noDriverFound(tester, drop);
      await pumpUntil(tester, () => backend.rideBookings.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PriceUpdatedDialog), findsNothing);
      expect(backend.rideBookings, hasLength(1));
      expect(bookedMinor(AppScope.instance.ride.rideId), drop);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ---------------------------------------------------------------- case 6
  // A driver was assigned (Waiting for driver), then the driver reports a
  // no-show -> end sheet -> "Relancer la recherche": the trip is priced again
  // (waiting_for_driver_stages.dart:84). Goes through the app's own
  // in-process server (AppScope), which prices from the route.
  group('case6 Waiting for driver: no-show -> Relancer la recherche', () {
    Future<MockRideRealtime> noShow(
      WidgetTester tester,
      int fresh, {
      int shown = first,
    }) async {
      phone(tester);
      RideSnapshotStore.epoch = 0;
      AppScope.instance.ride
        ..rideId = null
        ..suppressRestore = false
        ..authoritativeVersion = null
        ..authoritativeUpdatedAt = null
        ..restoreFromBackend(RideStatus.idle);
      final rideId = 'proof-no-show-$fresh-$shown';
      final destination = _dropFor[fresh] ?? _dropFor[drop]!;
      await RideSnapshotStore.save(
        RideSnapshot(
          status: RideStatus.driverAssigned,
          savedAt: DateTime.now(),
          pickupAddress: 'Rue de Rivoli 1, Paris',
          destinationAddress: 'Compiègne, Place du Palais',
          pickupLat: _pickup.latitude,
          pickupLng: _pickup.longitude,
          destinationLat: destination.latitude,
          destinationLng: destination.longitude,
          rideType: 'Movera',
          price: shown / 100,
          paymentMethod: 'Payer à bord',
          rideId: rideId,
        ),
      );
      AppScope.instance.ride
        ..restoreFromBackend(RideStatus.driverAssigned, id: rideId)
        ..bookedCategoryId = 'economy'
        ..bookedPaymentMethodId = 'cash';
      await tester.pumpWidget(_app(moveraNavigatorKey, 'accueil'));
      moveraNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => WaitingForDriver(
            pickupAddress: 'Rue de Rivoli 1, Paris',
            destinationAddress: 'Compiègne, Place du Palais',
            pickupPosition: _pickup,
            destinationPosition: destination,
            rideType: 'Movera',
            price: shown / 100,
            currency: 'EUR',
            paymentMethod: 'Payer à bord',
            categoryId: 'economy',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final realtime = AppScope.instance.rideRealtime as MockRideRealtime;
      realtime.holdAssignment();
      for (final step in [
        RideStatus.driverArriving,
        RideStatus.driverWaiting,
      ]) {
        realtime.emit(
          step,
          latitude: _pickup.latitude,
          longitude: _pickup.longitude,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      realtime.emit(RideStatus.noShow);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text(L10n.current.searchAgain), findsOneWidget);
      await tester.tap(find.text(L10n.current.searchAgain));
      for (
        var i = 0;
        i < 30 &&
            _dialog.evaluate().isEmpty &&
            find.byType(FindingDrivers).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      return realtime;
    }

    Future<void> run(WidgetTester tester, [int count = 30]) async {
      for (var i = 0; i < count; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    for (final (shown, fresh) in [(first, rise), (centFirst, cent)]) {
      testWidgets('case6: a rise ${eur(shown)} -> ${eur(fresh)} opens the v8 '
          'popup; the button opens a new search at it', (tester) async {
        await noShow(tester, fresh, shown: shown);
        expectPopup(shown, fresh);
        await shot(tester, 'case6-search-again-$fresh');
        await tester.tap(_accept);
        await run(tester);
        expect(find.byType(WaitingForDriver), findsNothing);
        final finding = tester.widget<FindingDrivers>(
          find.byType(FindingDrivers),
        );
        expect(finding.price, fresh / 100);
        expect(finding.currency, 'EUR');
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets('case6: ✕ books nothing and goes Home', (tester) async {
      await noShow(tester, rise);
      expectPopup(first, rise);
      await tester.tap(_close);
      await run(tester, 20);
      expect(find.byType(WaitingForDriver), findsNothing);
      expect(find.byType(FindingDrivers), findsNothing);
      expect(find.text('accueil'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('case6: a drop 79,30 -> 79,20 € opens no popup and opens the '
        'new search at 79,20 €', (tester) async {
      await noShow(tester, drop);
      await run(tester);
      expect(find.byType(PriceUpdatedDialog), findsNothing);
      final finding = tester.widget<FindingDrivers>(
        find.byType(FindingDrivers),
      );
      expect(finding.price, drop / 100);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
