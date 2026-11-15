import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    show GoogleMapsFlutterPlatform;
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/history/application/trip_path.dart';
import 'package:movera_rider/features/history/presentation/past_ride_route_map.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/fake_maps_platform.dart';

/// BQ-V16 (owner driver-g11.md:6, "must be for all apps live trip or
/// history including admin"): a past ride in History shows the route the
/// car really drove, read from `GET /trips/{tripId}/path`, not the drawn
/// stand-in. An old ride shows the server's planned route and says so; an
/// unreadable path shows the pins only (never a made-up line on live);
/// the demo keeps its drawing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoogleMapsFlutterPlatform previousPlatform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previousPlatform = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = FakeMapsPlatform();
    CustomGoogleMap.debugWaitForMaps = false;
  });

  tearDown(() {
    GoogleMapsFlutterPlatform.instance = previousPlatform;
    CustomGoogleMap.debugWaitForMaps = null;
    PastRideRouteMap.debugLive = null;
  });

  const driven = [
    GeoPoint(59.3410, 18.0500),
    GeoPoint(59.3440, 18.0400),
    GeoPoint(59.3480, 18.0320),
    GeoPoint(59.3600, 18.0010),
  ];

  TripPath path(TripPathSource source) => TripPath(
    source: source,
    points: driven,
    pickup: driven.first,
    dropoff: driven.last,
  );

  Reservation ride({bool savedPoints = true}) => Reservation(
    reservationId: 'ondemand-trip_v16',
    createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
    scheduledPickupAt: DateTime.now(),
    pickup: ReservationPlace(
      label: 'Odenplan',
      lat: savedPoints ? 59.3430 : null,
      lng: savedPoints ? 18.0490 : null,
    ),
    destination: ReservationPlace(
      label: 'Solna centrum',
      lat: savedPoints ? 59.3590 : null,
      lng: savedPoints ? 18.0000 : null,
    ),
    categoryId: 'economy',
    categoryName: 'Movera',
    categoryImage: 'assets/images/rides/movera.webp',
    price: 259,
    paymentMethod: 'Apple Pay',
    status: ReservationStatus.completed,
  );

  Future<List<String>> openPastRide(
    WidgetTester tester, {
    required Future<TripPath?> Function(String tripId) loader,
    Reservation? past,
  }) async {
    final asked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RideHistory(
          reservations: ReservationController(
            store: LocalReservationRepository(
              storage: MemoryReservationStorage(),
            ),
          ),
          onDemandReader: () async => [past ?? ride()],
          receiptLoader: (_) async => null,
          pathLoader: (id) {
            asked.add(id);
            return loader(id);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Solna centrum').first);
    await tester.pumpAndSettle();
    expect(find.text('Completed ride'), findsOneWidget);
    return asked;
  }

  CustomGoogleMap map(WidgetTester tester) =>
      tester.widget<CustomGoogleMap>(find.byType(CustomGoogleMap));

  List<LatLng> lineOf(CustomGoogleMap map) {
    final casing = map.polylines!.firstWhere(
      (p) => p.polylineId.value == 'past-route-casing',
    );
    return casing.points;
  }

  testWidgets('live: the past ride draws the driven path from the server', (
    tester,
  ) async {
    PastRideRouteMap.debugLive = true;
    final asked = await openPastRide(
      tester,
      loader: (_) async => path(TripPathSource.driven),
    );

    expect(asked, ['trip_v16']);
    expect(find.byType(ReservationRoutePreview), findsNothing);
    final shown = map(tester);
    expect(lineOf(shown), [
      for (final p in driven) LatLng(p.latitude, p.longitude),
    ]);
    expect(
      shown.markers!.map((m) => m.markerId.value),
      containsAll(['pickup', 'destination']),
    );
    expect(find.text('Planned route'), findsNothing);
  });

  testWidgets('live: an old ride shows the planned route and says so', (
    tester,
  ) async {
    PastRideRouteMap.debugLive = true;
    await openPastRide(
      tester,
      loader: (_) async => path(TripPathSource.planned),
    );

    expect(find.byType(ReservationRoutePreview), findsNothing);
    expect(lineOf(map(tester)), hasLength(driven.length));
    expect(find.text('Planned route'), findsOneWidget);
  });

  testWidgets('live: no path read shows the pins only, no line', (
    tester,
  ) async {
    PastRideRouteMap.debugLive = true;
    await openPastRide(tester, loader: (_) async => null);

    expect(find.byType(ReservationRoutePreview), findsNothing);
    final shown = map(tester);
    expect(shown.polylines, isEmpty);
    expect(shown.markers!.map((m) => m.markerId.value).toSet(), {
      'pickup',
      'destination',
    });
  });

  testWidgets('live: no path and no saved points shows no map at all', (
    tester,
  ) async {
    PastRideRouteMap.debugLive = true;
    await openPastRide(
      tester,
      loader: (_) async => null,
      past: ride(savedPoints: false),
    );

    expect(find.byType(ReservationRoutePreview), findsNothing);
    expect(find.byType(CustomGoogleMap), findsNothing);
  });

  testWidgets('demo: the drawing stays and the server is not asked', (
    tester,
  ) async {
    PastRideRouteMap.debugLive = false;
    final asked = await openPastRide(
      tester,
      loader: (_) async => path(TripPathSource.driven),
    );

    expect(asked, isEmpty);
    expect(find.byType(ReservationRoutePreview), findsOneWidget);
    expect(find.byType(CustomGoogleMap), findsNothing);
  });

  test('TripPath.fromJson reads the contract shape and refuses a bad one', () {
    final read = TripPath.fromJson({
      'tripId': 't1',
      'source': 'driven',
      'points': [
        {'lat': 59.1, 'lng': 18.1},
        {'lat': 59.2, 'lng': 18.2},
      ],
      'pickup': {'lat': 59.1, 'lng': 18.1},
      'dropoff': {'lat': 59.2, 'lng': 18.2},
      'stops': [
        {'lat': 59.15, 'lng': 18.15},
      ],
      'keptUntil': '2026-12-15T10:00:00.000Z',
    });
    expect(read!.source, TripPathSource.driven);
    expect(read.points, hasLength(2));
    expect(read.stops, hasLength(1));

    expect(
      TripPath.fromJson({
        'source': 'driven',
        'points': [
          {'lat': 59.1, 'lng': 18.1},
        ],
        'pickup': {'lat': 59.1, 'lng': 18.1},
        'dropoff': {'lat': 59.2, 'lng': 18.2},
      }),
      isNull,
      reason: 'one point is not a line',
    );
    expect(
      TripPath.fromJson({
        'source': 'guessed',
        'points': [
          {'lat': 59.1, 'lng': 18.1},
          {'lat': 59.2, 'lng': 18.2},
        ],
        'pickup': {'lat': 59.1, 'lng': 18.1},
        'dropoff': {'lat': 59.2, 'lng': 18.2},
      }),
      isNull,
    );
  });
}
