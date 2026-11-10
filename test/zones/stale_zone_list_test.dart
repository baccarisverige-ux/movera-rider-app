import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/lifecycle/app_lifecycle.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/rider_zones_controller.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/not_here_view.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Quotes implements QuoteRepository {
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
  }) async => RideQuote(
    id: 'q-$rideType',
    rideType: rideType,
    totalMinor: 25000,
    currency: 'TND',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    signedPayload: 'signature',
  );
}

/// Owner 2026-11-10 ("Yes, fix now"): a zone list kept on the device from
/// before Grand Tunis opened must not keep a Tunis pickup on "Movera is not
/// here yet". The kept list is read again when the app comes back and
/// before "not here"; a failed read is retried; the server is the judge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(RiderZones.useSamples);

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );
  const tunis = LatLng(36.8065, 10.1815);

  Map<String, Object?> answerWith(List<RiderZone> zones) => {
    'zones': [for (final z in zones) z.toJson()],
  };

  RiderZonesController controller(
    Future<http.Response> Function(http.Request r) handler, {
    List<Duration>? retryDelays,
  }) => RiderZonesController(
    api: ApiClient(env: staging, client: MockClient(handler)),
    store: MemoryRiderZonesStore(),
    retryDelays: retryDelays,
  );

  Future<void> pumpTunisPickup(
    WidgetTester tester,
    RiderZonesController zones,
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
      quotes: _Quotes(),
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Avenue Habib Bourguiba',
          destinationAddress: 'Tunis-Carthage',
          pickupPosition: tunis,
          destinationPosition: const LatLng(36.851, 10.2272),
          selection: selection,
          zones: zones,
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('stale device list, server lists TN-TC: Tunis is NOT "not '
      'here"', (tester) async {
    // The device kept the list from before Grand Tunis opened.
    RiderZones.useServer(const [RiderZones.france]);
    var reads = 0;
    final zones = controller((r) async {
      reads++;
      return http.Response(
        jsonEncode(answerWith(const [RiderZones.france, RiderZones.tunisia])),
        200,
      );
    });
    await pumpTunisPickup(tester, zones);
    expect(reads, 1, reason: 'the list is read before "not here"');
    expect(find.byType(NotHereView), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('the fresh list still leaves the pickup out: "not here"', (
    tester,
  ) async {
    RiderZones.useServer(const [RiderZones.france]);
    final zones = controller(
      (r) async =>
          http.Response(jsonEncode(answerWith(const [RiderZones.france])), 200),
    );
    await pumpTunisPickup(tester, zones);
    expect(find.byType(NotHereView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  test('coming back to the app reads the zones again', () {
    fakeAsync((async) {
      var reads = 0;
      final zones = controller((r) async {
        reads++;
        return http.Response(
          jsonEncode(answerWith(const [RiderZones.france])),
          200,
        );
      });
      AppLifecycleObserver(
        zones: zones,
      ).didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.elapse(const Duration(seconds: 1));
      expect(reads, 1);
    });
  });

  test('a failed read with an old copy in use is retried (bounded)', () {
    fakeAsync((async) {
      RiderZones.useServer(const [RiderZones.france]);
      var reads = 0;
      final zones = controller((r) async {
        reads++;
        if (reads < 3) return http.Response('{"code":"X"}', 503);
        return http.Response(
          jsonEncode(answerWith(const [RiderZones.france, RiderZones.tunisia])),
          200,
        );
      }, retryDelays: const [Duration(seconds: 1), Duration(seconds: 2)]);
      zones.refresh();
      async.elapse(const Duration(seconds: 10));
      expect(reads, 3);
      expect(RiderZones.serves(tunis.latitude, tunis.longitude), isTrue);
    });
  });

  test('retries stop after the last delay', () {
    fakeAsync((async) {
      RiderZones.useServer(const [RiderZones.france]);
      var reads = 0;
      final zones = controller((r) async {
        reads++;
        return http.Response('{"code":"X"}', 503);
      }, retryDelays: const [Duration(seconds: 1), Duration(seconds: 2)]);
      zones.refresh();
      async.elapse(const Duration(minutes: 5));
      expect(reads, 3);
    });
  });
}
