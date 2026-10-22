import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    totalMinor: stops.isEmpty ? 25900 : 31900,
    currency: 'SEK',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    signedPayload: 'signature',
  );
}

/// rider-r4-28: Book for later priced and showed the stops, then saved the
/// reservation (and so its live ride) without them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('the stops the rider was quoted for are booked, kept and '
      'reach the live ride', (tester) async {
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
      quotes: _Quotes(),
      flags: FeatureFlags(),
    );
    addTearDown(selection.dispose);
    final storage = MemoryReservationStorage();
    final reservations = ReservationController(
      store: LocalReservationRepository(storage: storage),
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
          initialScheduledFor: StockholmSchedule.clampPickup(
            StockholmSchedule.stockholmNow().add(const Duration(days: 1)),
          ),
          onScheduled: (_, _) async {},
        ),
      ),
    );
    Future<void> settle([int steps = 10]) async {
      for (var i = 0; i < steps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.tap(find.text('Schedule Movera'));
    await settle(30);
    await tester.tap(find.text('Confirm and schedule'));
    await settle(30);

    final booked = reservations.all.single;
    expect(booked.price, 319);
    const stop = {'label': 'KTH Campus', 'lat': 59.35, 'lng': 18.07};
    expect(booked.toJson()['stops'], [stop]);
    // Saved and read back (the app restarts), and on the live ride at T-2.
    final saved = Reservation.tryParse(
      (jsonDecode(storage.value!) as List).single,
    )!;
    expect(saved.toJson()['stops'], [stop]);
    final live = ReservationLiveRide.pageFor(saved, controller: reservations);
    expect(
      [for (final s in live.stops) s.toJson()],
      [
        {'address': 'KTH Campus', 'lat': 59.35, 'lng': 18.07},
      ],
    );
    // A reservation saved before stops existed still loads, with none.
    final legacy = Map<String, dynamic>.from(saved.toJson())..remove('stops');
    expect(Reservation.tryParse(legacy)?.toJson().containsKey('stops'), false);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('changing a booked ride starts from its stops', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ride = Reservation.tryParse({
      'reservationId': 'rsv_1',
      'createdAt': '2026-10-20T10:00:00Z',
      'scheduledPickupAt': '2026-10-22T08:00:00Z',
      'pickup': {'label': 'Klockarvägen 37', 'lat': 59.3, 'lng': 18.0},
      'destination': {'label': 'Arlanda Airport', 'lat': 59.6, 'lng': 17.9},
      'stops': [
        {'label': 'KTH Campus', 'lat': 59.35, 'lng': 18.07},
      ],
    })!;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(home: ScheduleRide(editing: ride)),
      ),
    );
    await tester.pump();
    expect(find.text('KTH Campus'), findsOneWidget);
    expect(find.text('Stop 1'), findsOneWidget);
  });
}
