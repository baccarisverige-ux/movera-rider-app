import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride_geometry.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class _ImmediateQuotes implements QuoteRepository {
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
  }) => Future<RideQuote>.value(
    RideQuote(
      id: 'q-$rideType',
      rideType: rideType,
      totalMinor: 25900,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      signedPayload: 'sig',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> openSelectRide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selection = RideSelectionController(quotes: _ImmediateQuotes());
    addTearDown(selection.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('home')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.selectRide),
        builder: (_) => SelectRide(
          pickupAddress: 'Stockholm Central',
          destinationAddress: 'Odenplan',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3429, 18.0496),
          pickupAlreadyConfirmed: true,
          selection: selection,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('D-006: no price stepper that can only dead-end', (tester) async {
    await openSelectRide(tester);
    final inSelectRide = find.descendant(
      of: find.byType(SelectRide),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.remove_rounded || w.icon == Icons.add_rounded),
      ),
    );
    expect(inSelectRide, findsNothing);
  });

  testWidgets('N6: the Select ride map stays flat (no tilt with zoom)', (
    tester,
  ) async {
    // Owner screenshot (Select ride, Klockarvägen 37, Södertälje): the fit
    // leaned the camera 67.5° at building level and the route line became a
    // wedge. Select ride reads the route from above; Home keeps the driver
    // app's tilt-with-zoom camera. (Finding and the trip map: their own
    // screen tests.)
    await openSelectRide(tester);
    // The map mounts once the route transition has settled.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final maps = find.descendant(
      of: find.byType(SelectRide),
      matching: find.byType(CustomGoogleMap),
    );
    expect(maps, findsWidgets);
    for (final map in tester.widgetList<CustomGoogleMap>(maps)) {
      expect(map.tiltWithZoom, isFalse);
    }
  });

  test('D-007: the map uses the confirmed pickup, not the constructor one', () {
    final src = File(
      'lib/features/ride_selection/presentation/select_ride.dart',
    ).readAsStringSync();
    // The only read of widget.pickupPosition is seeding _pickupPosition in
    // initState; markers, route, initial camera and fitBounds must all follow
    // _pickupPosition so a re-confirmed pickup is what the rider sees.
    expect(RegExp(r'widget\.pickupPosition').allMatches(src).length, 1);
    expect(src, contains('_pickupPosition = widget.pickupPosition;'));
  });

  group('D-009: the map is visible above the ride sheet', () {
    test('owner round 2: fully up, the sheet goes near the top and leaves a '
        'strip of map', () {
      const media = MediaQueryData(
        size: Size(390, 844),
        padding: EdgeInsets.only(top: 47),
      );
      final maxSheet = selectRideMaxSheetHeight(media);
      expect(844 - 47 - maxSheet, selectRideFullTopGap);
      expect(selectRideFullTopGap, inInclusiveRange(32, 80));
    });

    test('large text still gets the full height it needs', () {
      const media = MediaQueryData(
        size: Size(390, 844),
        textScaler: TextScaler.linear(2),
      );
      expect(selectRideMaxSheetHeight(media), 844);
    });

    test('both pins are framed in the part of the map the sheet leaves', () {
      const pickup = GeoPoint(59.3293, 18.0686);
      const destination = GeoPoint(59.3429, 18.0496);
      final fit = selectRideCameraFit(
        pickup: pickup,
        destination: destination,
        mapHeight: 496,
        bottomObstruction: 210,
      );
      expect(fit.northeast.latitude, destination.latitude);
      expect(fit.northeast.longitude, pickup.longitude);
      expect(fit.southwest.longitude, destination.longitude);
      // Only the south edge is stretched, by the covered share of the map.
      final span = destination.latitude - pickup.latitude;
      final full = 496 - 2 * fit.padding;
      final usable = 496 - 210 - 2 * fit.padding;
      expect(
        fit.southwest.latitude,
        closeTo(destination.latitude - span * full / usable, 1e-9),
      );
    });
  });

  group('owner round 4: the camera frames the road and the bubbles', () {
    const pickup = GeoPoint(59.3293, 18.0686);
    const destination = GeoPoint(59.3429, 18.0496);

    test('the road route widens the bounds past the straight line', () {
      final fit = selectRideCameraFit(
        pickup: pickup,
        destination: destination,
        mapHeight: 496,
        bottomObstruction: 0,
        route: const [
          pickup,
          GeoPoint(59.3300, 18.0900), // a detour east of both pins
          GeoPoint(59.3500, 18.0600), // and north of the destination
          destination,
        ],
      );
      expect(fit.northeast.longitude, 18.0900);
      expect(fit.northeast.latitude, 59.3500);
      expect(fit.southwest.longitude, destination.longitude);
      expect(fit.southwest.latitude, pickup.latitude);
    });

    test('the search bar at the top stretches the bounds north', () {
      final fit = selectRideCameraFit(
        pickup: pickup,
        destination: destination,
        mapHeight: 496,
        bottomObstruction: 0,
        topObstruction: 100,
      );
      final span = destination.latitude - pickup.latitude;
      final usable = 496 - 100 - 2 * fit.padding;
      expect(
        fit.northeast.latitude,
        closeTo(destination.latitude + span * (100 / usable), 1e-9),
      );
      expect(fit.southwest.latitude, pickup.latitude);
    });

    test('the padding leaves room for a time bubble beside the edge', () {
      final fit = selectRideCameraFit(
        pickup: pickup,
        destination: destination,
        mapHeight: 496,
        bottomObstruction: 0,
      );
      // Half of a ~110 px bubble plus a margin.
      expect(fit.padding, greaterThanOrEqualTo(70));
      expect(fit.padding, selectRideEdgePadding);
    });
  });
}
