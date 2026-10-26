import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/nearby_car.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_picture.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// Owner (iPhone PWA): the categories sheet was slow to slide. The sheet
/// moves over the map, which on the web is a platform view, so every frame
/// of the drag already costs the engine a re-composite; on top of that each
/// drag tick rebuilt the whole sheet (every row, its fonts and times) and
/// the cars gliding on the map redrew the map under the finger. These pin
/// the structure that keeps a drag tick cheap
/// (docs/select-ride-sheet-performance.md).

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

/// One car that is somewhere else on every answer, so the map glides it
/// (80 ms ticks) after each one.
class _MovingCar implements NearbyCarsSource {
  int answers = 0;

  @override
  Future<NearbyCarsAnswer> near(GeoPoint point) async {
    answers += 1;
    return NearbyCarsAnswer(
      cars: [
        NearbyCar(
          key: 'car-1',
          latitude: 59.3326 + 0.002 * answers,
          longitude: 18.0649,
          heading: 90,
        ),
      ],
      refresh: const Duration(milliseconds: 500),
    );
  }
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

  Future<RideSelectionController> pumpSelectRide(
    WidgetTester tester, {
    NearbyCarsSource? cars,
  }) async {
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
          nearbyCars: cars ?? _NoCars(),
        ),
      ),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('select-ride-map')), findsOneWidget);
    return selection;
  }

  /// A finger on the title row, moved [steps] times by [step] with a frame
  /// between each move; left down.
  Future<TestGesture> dragSheet(
    WidgetTester tester, {
    required Offset step,
    int steps = 12,
  }) async {
    final handle = find.byKey(const ValueKey('select-ride-sheet-handle'));
    final start = tester.getCenter(handle) + const Offset(0, 32);
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  testWidgets(
    'a drag tick rebuilds neither the map nor the rows, only what moves',
    (tester) async {
      await pumpSelectRide(tester);
      final map = find.byKey(const ValueKey('select-ride-map'));
      final list = find.byKey(const ValueKey('select-ride-list'));
      final mapBefore = tester.widget<CustomGoogleMap>(map);
      final listBefore = tester.widget<ListView>(list);
      final firstRowBefore = tester.widget<RidePicture>(
        find.byType(RidePicture).first,
      );
      final topBefore = sheetTop(tester);

      // Up from the middle stop towards the full stop (the descriptions
      // grow in), and back down past the middle (the list fades out).
      var gesture = await dragSheet(tester, step: const Offset(0, -20));
      expect(sheetTop(tester), lessThan(topBefore - 100));
      expect(identical(tester.widget<CustomGoogleMap>(map), mapBefore), isTrue);
      expect(identical(tester.widget<ListView>(list), listBefore), isTrue);
      expect(
        identical(
          tester.widget<RidePicture>(find.byType(RidePicture).first),
          firstRowBefore,
        ),
        isTrue,
      );
      await gesture.up();
      await settle(tester);

      gesture = await dragSheet(tester, step: const Offset(0, 30), steps: 14);
      expect(sheetTop(tester), greaterThan(topBefore + 60));
      expect(identical(tester.widget<CustomGoogleMap>(map), mapBefore), isTrue);
      expect(identical(tester.widget<ListView>(list), listBefore), isTrue);
      await gesture.up();
      await settle(tester);
    },
  );

  testWidgets('the descriptions and the low row still follow the sheet', (
    tester,
  ) async {
    await pumpSelectRide(tester);
    // The first ride's description, clipped to nothing until the sheet is
    // fully up.
    double descriptionHeight() => tester
        .getSize(
          find
              .ancestor(
                of: find.text('Affordable and convenient rides').first,
                matching: find.byType(ClipRect),
              )
              .first,
        )
        .height;
    // Middle stop: no description, the chosen ride's low row is off.
    expect(descriptionHeight(), 0);
    expect(
      find.byKey(const ValueKey('select-ride-low-row-drag')),
      findsNothing,
    );
    final gesture = await dragSheet(
      tester,
      step: const Offset(0, -30),
      steps: 14,
    );
    await gesture.up();
    await settle(tester);
    // Full: the descriptions are in.
    expect(descriptionHeight(), greaterThan(10));

    final down = await dragSheet(tester, step: const Offset(0, 40), steps: 14);
    await down.up();
    await settle(tester);
    // Low stop: only the chosen ride, the list faded out under it.
    expect(
      find.byKey(const ValueKey('select-ride-low-row-drag')),
      findsOneWidget,
    );
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('select-ride-list')),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 0);
  });

  testWidgets('no camera update while the finger moves; one when it settles', (
    tester,
  ) async {
    final fits = <GeoPoint>[];
    AppScope.instance.maps.debugOnFitBounds = (_, a, __) => fits.add(a);
    AppScope.instance.maps.debugOnCameraCommand = (_, target) =>
        fits.add(target);
    addTearDown(() {
      AppScope.instance.maps
        ..debugOnFitBounds = null
        ..debugOnCameraCommand = null;
    });
    await pumpSelectRide(tester);
    fits.clear();

    final gesture = await dragSheet(
      tester,
      step: const Offset(0, -20),
      steps: 14,
    );
    expect(fits, isEmpty, reason: 'the camera stays put under the finger');
    await gesture.up();
    await settle(tester);
    expect(fits.length, 1, reason: 'one fit for the stop it settles on');
  });

  testWidgets('the gliding cars do not redraw the map under the finger', (
    tester,
  ) async {
    final cars = _MovingCar();
    await pumpSelectRide(tester, cars: cars);
    final map = find.byKey(const ValueKey('select-ride-map'));
    // The first answer is in; the second (a moved car) lands 500 ms later
    // and starts a glide of 80 ms ticks.
    expect(cars.answers, greaterThanOrEqualTo(1));
    final mapBefore = tester.widget<CustomGoogleMap>(map);

    final gesture = await dragSheet(
      tester,
      step: const Offset(0, -4),
      steps: 50,
    );
    expect(cars.answers, greaterThanOrEqualTo(2));
    expect(
      identical(tester.widget<CustomGoogleMap>(map), mapBefore),
      isTrue,
      reason: 'no glide tick reaches the map while the sheet is dragged',
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      identical(tester.widget<CustomGoogleMap>(map), mapBefore),
      isFalse,
      reason: 'the cars catch up once the finger lets go',
    );
    await settle(tester);
  });
}
