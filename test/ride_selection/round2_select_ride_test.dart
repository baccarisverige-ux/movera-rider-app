import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/domain/nearby_car.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_picture.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';

/// Owner round 2 on Select ride: the ride pictures and the nearby cars.

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

class _Cars implements NearbyCarsSource {
  final asked = <GeoPoint>[];

  @override
  Future<NearbyCarsAnswer> near(GeoPoint point) async {
    asked.add(point);
    return const NearbyCarsAnswer(
      cars: [
        NearbyCar(
          key: 'abc123',
          latitude: 59.33,
          longitude: 18.07,
          heading: 80,
        ),
      ],
      refresh: Duration(seconds: 5),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the ride picture', () {
    test('the van for the big types, a longer car for Premium', () {
      expect(RidePicture.isVan('xl', null), isTrue);
      expect(RidePicture.isVan('van', null), isTrue);
      expect(RidePicture.isVan('wheelchair', null), isTrue);
      expect(RidePicture.isVan('taxi_plus', 'van'), isTrue);
      expect(RidePicture.isVan('economy', null), isFalse);
      expect(RidePicture.isLong('premium'), isTrue);
      expect(RidePicture.isLong('economy'), isFalse);
    });

    test('what stands beside the car, as the owner chose', () {
      expect(RidePicture.extraFor('economy', null), RideExtra.none);
      expect(RidePicture.extraFor('comfort', null), RideExtra.none);
      expect(RidePicture.extraFor('xl', 'van'), RideExtra.none);
      expect(RidePicture.extraFor('premium', null), RideExtra.none);
      expect(RidePicture.extraFor('priority', null), RideExtra.priority);
      expect(RidePicture.extraFor('electric', 'bolt'), RideExtra.charger);
      expect(RidePicture.extraFor('pet', 'pets'), RideExtra.paw);
      expect(RidePicture.extraFor('kids', 'child'), RideExtra.babySeat);
      // Types the admin adds later: by their glyph.
      expect(RidePicture.extraFor('green', 'bolt'), RideExtra.charger);
      expect(RidePicture.extraFor('airport', 'plane'), RideExtra.icon);
      expect(RidePicture.extraFor('wheelchair', 'wheelchair'), RideExtra.icon);
      expect(RidePicture.extraFor('new_type', null), RideExtra.none);
    });

    testWidgets('draws the car, the van and the extras', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                RidePicture(rideId: 'economy'),
                RidePicture(rideId: 'xl', glyph: 'van'),
                RidePicture(rideId: 'electric', glyph: 'bolt'),
                RidePicture(rideId: 'kids', glyph: 'child'),
                RidePicture(rideId: 'priority'),
                RidePicture(rideId: 'pet', glyph: 'pets'),
                RidePicture(rideId: 'premium'),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('ride-picture-car')), findsNWidgets(6));
      expect(find.byKey(const ValueKey('ride-picture-van')), findsOneWidget);
      expect(find.byKey(const ValueKey('ride-extra-charger')), findsOneWidget);
      expect(find.byKey(const ValueKey('ride-extra-babySeat')), findsOneWidget);
      expect(find.byKey(const ValueKey('ride-extra-priority')), findsOneWidget);
      expect(find.byKey(const ValueKey('ride-extra-paw')), findsOneWidget);
      // Premium's car is longer than Economy's, not taller.
      final cars = find.byKey(const ValueKey('ride-picture-car'));
      final economy = tester.getSize(cars.at(0));
      final premium = tester.getSize(cars.at(5));
      expect(premium.width, greaterThan(economy.width * 1.1));
      expect(premium.height, economy.height);
    });
  });

  testWidgets(
    'asks for the cars around the pickup while the screen shows, and stops when it leaves',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selection = RideSelectionController(quotes: _Quotes());
      addTearDown(selection.dispose);
      final cars = _Cars();
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
            pickupAddress: 'Sergels torg',
            destinationAddress: 'Odenplan',
            pickupPosition: const LatLng(59.3326, 18.0649),
            destinationPosition: const LatLng(59.3429, 18.0496),
            pickupAlreadyConfirmed: true,
            selection: selection,
            nearbyCars: cars,
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(cars.asked, isNotEmpty);
      expect(cars.asked.first.latitude, 59.3326);
      expect(cars.asked.first.longitude, 18.0649);
      // Again after refreshSeconds.
      final before = cars.asked.length;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(cars.asked.length, greaterThan(before));

      // Leaving the screen stops asking.
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final after = cars.asked.length;
      await tester.pump(const Duration(seconds: 30));
      expect(cars.asked.length, after);
    },
  );
}
