import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tree_snapshot.dart';

// Base job 2 (2026-11-04): the three rider screens split with no behaviour
// change. Each snapshot was written before the split and must match after it.

class _Feed extends RideRealtime {
  final events = StreamController<RideRealtimeEvent>.broadcast();
  var _seq = 0;
  void add(RideStatus status, MatchedDriver driver) => events.add(
    RideRealtimeEvent(
      rideId: 'split-1',
      status: status,
      sequence: ++_seq,
      version: _seq,
      driver: driver,
    ),
  );
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => events.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void dispose() {}
}

class _Geocoder implements GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async =>
      PlaceResult(address: query, point: const GeoPoint(59.35, 18.07));
  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

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
    totalMinor: 25900,
    currency: 'SEK',
    expiresAt: DateTime.utc(2030),
    signedPayload: 'signature',
  );
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false;
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('waiting_for_driver: driver on the way, then waiting', (
    tester,
  ) async {
    phone(tester);
    AppScope.instance.ride.restoreFromBackend(
      RideStatus.driverAssigned,
      id: 'split-1',
    );
    const driver = MatchedDriver(id: 'd1', firstName: 'Anna');
    final feed = _Feed();
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.33, 18.07),
          destinationPosition: const LatLng(59.34, 18.06),
          rideType: 'Movera',
          price: 259,
          paymentMethod: 'Apple Pay',
          driver: driver,
          realtime: feed,
        ),
      ),
    );
    await _frames(tester, 10);
    expectTreeSnapshot(tester, 'rider_waiting_for_driver_assigned');
    feed.add(RideStatus.driverWaiting, driver);
    await _frames(tester, 10);
    expectTreeSnapshot(tester, 'rider_waiting_for_driver_waiting');
    await tester.pumpWidget(const SizedBox());
    await _frames(tester, 5);
  });

  testWidgets('select_ride: route with one stop', (tester) async {
    phone(tester);
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
    final reservations = ReservationController(
      store: LocalReservationRepository(storage: MemoryReservationStorage()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.6519, 17.9186),
          stops: const ['KTH Campus'],
          geocoding: _Geocoder(),
          selection: selection,
          reservations: reservations,
        ),
      ),
    );
    await _frames(tester, 20);
    expectTreeSnapshot(tester, 'rider_select_ride');
  });

  testWidgets('home: first screen', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    await _frames(tester, 10);
    expectTreeSnapshot(tester, 'rider_home');
    debugDefaultTargetPlatformOverride = null;
  });
}
