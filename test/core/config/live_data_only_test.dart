// L-a R1/R3 (owner Q5 A, 2026-11-06): a live build shows "Checking your
// area…" and no sample zones or prices until the server answers; when the
// read fails, an error with Retry. Demo builds and tests keep the samples.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/config/live_data_only.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/rider_zones_controller.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/checking_area_view.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );
  final riderConfig =
      jsonDecode(
            File(
              'contracts/fixtures/config/rider_app_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final zonesAnswer = {
    'zones': [RiderZones.france.toJson()],
  };

  ApiClient api(Future<http.Response> Function(http.Request r) handler) =>
      ApiClient(env: staging, client: MockClient(handler));
  Future<http.Response> offline(http.Request _) async =>
      throw const SocketException('offline');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RiderZones.useSamples();
    LiveDataOnly.on = true;
  });
  tearDown(() {
    LiveDataOnly.on = false;
    RiderZones.useSamples();
  });

  group('live, before the server answers', () {
    test('no sample zones: nothing known, nothing served by a box', () {
      expect(RiderZones.known, isFalse);
      expect(RiderZones.all, isEmpty);
      expect(RiderZones.cityNames('en'), isEmpty);
      // Tunis and Paris were "served" by the built-in sample boxes.
      expect(RiderZones.find(36.8, 10.18), isNull);
      expect(RiderZones.find(48.85, 2.35), isNull);
      expect(seedConfigForTrip('TND'), isNull);
      expect(seedConfigForTrip('SEK'), isNull);
    });

    test(
      'config read fails, cache empty: no price, no sample catalog',
      () async {
        final repo = ApiRiderConfigRepository(
          api: api(offline),
          cache: MemoryRiderConfigCache(),
          homeZoneId: 'Z001',
        );
        await expectLater(repo.currentServed(), throwsStateError);
        final catalog = RideCatalogController(
          api: api(offline),
          cache: MemoryRideCatalogCache(),
          configSource: repo.currentServed,
        );
        await catalog.load();
        expect(catalog.source, RideCatalogSource.builtIn);
        final selection = RideSelectionController(
          catalog: catalog,
          quotes: CatalogQuoteRepository(),
          flags: FeatureFlags(),
        );
        for (final ride in selection.rides()) {
          expect(
            selection.hasPriceFor(ride.id, catalogCurrency: ride.currency),
            isFalse,
            reason: '${ride.id}: the built-in list price is a sample',
          );
        }
      },
    );

    testWidgets('Select ride shows "Checking your area…", no price', (
      tester,
    ) async {
      final zones = RiderZonesController(
        api: api((_) async => http.Response(jsonEncode(zonesAnswer), 200)),
        store: MemoryRiderZonesStore(),
      );
      await tester.pumpWidget(_app(CheckingAreaView(zones: zones)));
      expect(find.text('Checking your area…'), findsOneWidget);
      expect(find.byKey(const ValueKey('checking-area-retry')), findsNothing);
      expect(find.textContaining('kr'), findsNothing);
      expect(find.textContaining('TND'), findsNothing);
    });
  });

  group('after the server answers', () {
    test('real zones and the served config and catalog', () async {
      final zones = RiderZonesController(
        api: api((_) async => http.Response(jsonEncode(zonesAnswer), 200)),
        store: MemoryRiderZonesStore(),
      );
      expect(await zones.refresh(), isTrue);
      expect(RiderZones.known, isTrue);
      expect(RiderZones.all.map((z) => z.id), ['FR-PC']);
      expect(RiderZones.find(36.8, 10.18), isNull, reason: 'Tunis not listed');
      expect(zones.failed, isFalse);

      final repo = ApiRiderConfigRepository(
        api: api(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode(riderConfig)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
        cache: MemoryRiderConfigCache(),
        homeZoneId: 'Z001',
      );
      final served = await repo.currentServed();
      expect(served.zoneId, 'Z001');
      expect(repo.isServerDocument(served), isTrue);
      final catalog = RideCatalogController(
        api: api(offline),
        cache: MemoryRideCatalogCache(),
        configSource: repo.currentServed,
      );
      await catalog.load();
      expect(catalog.source, RideCatalogSource.server);
      final selection = RideSelectionController(
        catalog: catalog,
        quotes: CatalogQuoteRepository(),
        flags: FeatureFlags(),
        currency: served.currency,
      );
      final economy = selection.rides().firstWhere((r) => r.id == 'economy');
      expect(
        selection.hasPriceFor('economy', catalogCurrency: economy.currency),
        isTrue,
      );
    });
  });

  group('when it fails', () {
    testWidgets('an error with Retry, and Retry reads the server again', (
      tester,
    ) async {
      var up = false;
      var calls = 0;
      final zones = RiderZonesController(
        api: api((_) async {
          calls++;
          if (!up) throw const SocketException('offline');
          return http.Response(jsonEncode(zonesAnswer), 200);
        }),
        store: MemoryRiderZonesStore(),
      );
      await tester.pumpWidget(_app(CheckingAreaView(zones: zones)));
      await tester.runAsync(zones.refresh);
      await tester.pump();
      expect(zones.failed, isTrue);
      expect(find.text('Checking your area…'), findsNothing);
      expect(
        find.text(
          'Movera could not check your area. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('checking-area-retry')), findsOneWidget);

      up = true;
      await tester.tap(find.byKey(const ValueKey('checking-area-retry')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.runAsync(zones.refresh);
      await tester.pump();
      expect(calls, greaterThanOrEqualTo(2));
      expect(zones.failed, isFalse);
      expect(RiderZones.known, isTrue);
      expect(RiderZones.all.single.id, 'FR-PC');
    });
  });

  group('demo and tests keep the samples', () {
    test('LiveDataOnly off: samples, known, seed config', () {
      LiveDataOnly.on = false;
      expect(RiderZones.known, isTrue);
      expect(RiderZones.all, RiderZones.samples);
      expect(seedConfigForTrip('TND'), isNotNull);
    });
  });

  for (final (code, text, retry) in [
    ('sv', 'Kontrollerar ditt område…', 'Försök igen'),
    ('fr', 'Vérification de votre zone…', 'Réessayer'),
  ]) {
    testWidgets('CheckingAreaView in $code', (tester) async {
      L10n.use(code);
      addTearDown(() => L10n.use('en'));
      final zones = RiderZonesController(
        api: api(offline),
        store: MemoryRiderZonesStore(),
      );
      await tester.pumpWidget(_app(CheckingAreaView(zones: zones), code));
      expect(find.text(text), findsOneWidget);
      await tester.runAsync(zones.refresh);
      await tester.pump();
      expect(find.text(retry), findsOneWidget);
    });
  }
}

Widget _app(Widget home, [String code = 'en']) => MaterialApp(
  locale: Locale(code),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);
