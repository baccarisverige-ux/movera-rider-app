import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/nearby_car.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';

/// Owner round 3 on Select ride: the whole sheet answers a swipe, even the
/// chosen ride at the low stop and the payment block under it.

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

class _NoCars implements NearbyCarsSource {
  @override
  Future<NearbyCarsAnswer> near(GeoPoint point) async =>
      const NearbyCarsAnswer(cars: [], refresh: Duration(seconds: 30));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  double sheetTop(WidgetTester tester) => tester
      .getTopLeft(find.byKey(const ValueKey('select-ride-sheet-handle')))
      .dy;

  testWidgets('a swipe on the payment block or the low row moves the sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selection = RideSelectionController(quotes: _Quotes());
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SelectRide(
          pickupAddress: 'Sergels torg',
          destinationAddress: 'Odenplan',
          pickupPosition: const LatLng(59.3326, 18.0649),
          destinationPosition: const LatLng(59.3429, 18.0496),
          pickupAlreadyConfirmed: true,
          selection: selection,
          nearbyCars: _NoCars(),
        ),
      ),
    );
    await settle(tester);
    final footer = find.byKey(const ValueKey('select-ride-footer-drag'));
    expect(footer, findsOneWidget);

    // Down from the payment block: the sheet goes to the low stop.
    final mid = sheetTop(tester);
    await tester.timedDragFrom(
      tester.getTopLeft(footer) + const Offset(40, 8),
      const Offset(0, 300),
      const Duration(milliseconds: 300),
    );
    await settle(tester);
    final low = sheetTop(tester);
    expect(low, greaterThan(mid + 40));

    // Up from the chosen ride shown at the low stop.
    final row = find.byKey(const ValueKey('select-ride-low-row-drag'));
    expect(row, findsOneWidget);
    await tester.timedDragFrom(
      tester.getCenter(row),
      const Offset(0, -200),
      const Duration(milliseconds: 300),
    );
    await settle(tester);
    expect(sheetTop(tester), lessThan(low - 40));
  });
}
