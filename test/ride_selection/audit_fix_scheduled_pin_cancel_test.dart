import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _origin = LatLng(59.3293, 18.0686);

/// 259 kr at the original pickup, 301 kr anywhere else.
class _PinQuotes implements QuoteRepository {
  _PinQuotes({this.originMinor = 25900});

  final int originMinor;
  int calls = 0;

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
    calls++;
    final atOrigin =
        pickupPoint == null ||
        (pickupPoint.latitude - _origin.latitude).abs() < 1e-6;
    return RideQuote(
      id: 'q-$rideType-$calls',
      rideType: rideType,
      totalMinor: atOrigin ? originMinor : 30100,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      signedPayload: 'signature',
    );
  }
}

/// rider-u188: backing out of Set pickup in Book for later after the pin
/// was priced puts back the original pickup's price.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('a cancelled Set pickup does not keep the pin price', (
    tester,
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
      quotes: _PinQuotes(),
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    final reservations = ReservationController(
      store: LocalReservationRepository(storage: MemoryReservationStorage()),
    );
    final pickupAt = StockholmSchedule.clampPickup(
      StockholmSchedule.stockholmNow().add(const Duration(days: 1)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: _origin,
          destinationPosition: const LatLng(59.6519, 17.9186),
          selection: selection,
          reservations: reservations,
          initialScheduledFor: pickupAt,
        ),
      ),
    );
    Future<void> settle([int steps = 10]) async {
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    expect(selection.authoritativeQuotes['economy']?.totalMinor, 25900);

    await tester.tap(find.text('Schedule Movera'));
    await settle(30);
    expect(find.byType(SetPickupPage), findsOneWidget);
    final map = tester.widget<CustomGoogleMap>(
      find.byKey(const ValueKey('set-pickup-map')),
    );
    map.onCameraMoveStarted!();
    map.onCameraMove!(
      const CameraPosition(target: LatLng(59.31, 18.0686), zoom: 16),
    );
    map.onCameraIdle!();
    await settle();
    expect(find.text('301 kr'), findsWidgets);

    // The rider changes their mind and goes back.
    await tester.tap(find.byTooltip('Back'));
    await settle(20);
    expect(find.byType(SetPickupPage), findsNothing);
    expect(selection.authoritativeQuotes['economy']?.totalMinor, 25900);
    expect(selection.priceFor('economy', 259), 259);

    // Set pickup opens at the original point with its own price.
    await tester.tap(find.text('Schedule Movera'));
    await settle(30);
    expect(find.byType(SetPickupPage), findsOneWidget);
    expect(find.text('301 kr'), findsNothing);
    expect(find.text('259 kr'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  /// Book for later on Select Ride, quoted by [quotes]; [pickupAt] null
  /// opens the date picker on Book.
  Future<RideSelectionController> pumpScheduled(
    WidgetTester tester,
    _PinQuotes quotes, {
    DateTime? pickupAt,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selection = RideSelectionController(
      catalog: RideCatalogController(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(jsonEncode({'code': 'X'}), 500),
          ),
        ),
        cache: MemoryRideCatalogCache(),
      ),
      quotes: quotes,
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Klockarvägen 37',
          destinationAddress: 'Arlanda Airport',
          pickupPosition: _origin,
          destinationPosition: const LatLng(59.6519, 17.9186),
          selection: selection,
          reservations: ReservationController(
            store: LocalReservationRepository(
              storage: MemoryReservationStorage(),
            ),
          ),
          bookingMode: BookingMode.scheduled,
          initialScheduledFor: pickupAt,
        ),
      ),
    );
    await settleFor(tester);
    return selection;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('rider-r4-30: Set pickup after a long date picker shows a live '
      'quote, never the list price', (tester) async {
    final selection = await pumpScheduled(
      tester,
      _PinQuotes(originMinor: 24500),
    );
    await tester.tap(find.text('Schedule Movera'));
    await settleFor(tester, 20);
    expect(find.byKey(const Key('schedule-continue')), findsOneWidget);
    // Minutes in the date picker: the quote runs out.
    selection.quoteExpiresAt['economy'] = DateTime.now().subtract(
      const Duration(seconds: 1),
    );
    await tester.tap(find.byKey(const Key('schedule-continue')));
    await settleFor(tester, 30);
    expect(find.byType(SetPickupPage), findsOneWidget);
    expect(find.text('259 kr'), findsNothing);
    expect(find.text('245 kr'), findsWidgets);
    await unmount(tester);
  });
}

Future<void> settleFor(WidgetTester tester, [int steps = 10]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
