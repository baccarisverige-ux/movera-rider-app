import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/features/pickup/application/pickup_controller.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// Location allowed; the one-shot fix never answers (geolocator_web's
/// microsecond timeLimit, D-003).
class _HangingLocation extends LocationRepository {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Completer<Position>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('rider-u134: My location gives up with "unavailable" instead '
      'of hanging', (tester) async {
    final pickup = PickupMapController(
      location: _HangingLocation(),
      geocoding: AppGeocoding(),
    );
    PickupCurrentPositionResult? result;
    unawaited(pickup.currentPosition().then((value) => result = value));
    await tester.pump(const Duration(seconds: 30));
    expect(result, isNotNull);
    expect(result!.position, isNull);
    expect(result!.failure, PickupLocationFailure.unavailable);
    pickup.dispose();
  });

  group('rider-u136: Confirm pickup spot never names the new point with the '
      'previous address', () {
    const start = LatLng(59.19, 17.62);
    const moved = LatLng(59.1950, 17.6260);

    Future<Future<ConfirmPickupResult?>> open(WidgetTester tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('beneath'))),
        ),
      );
      final result = navigatorKey.currentState!.push<ConfirmPickupResult?>(
        MaterialPageRoute(
          builder: (_) => const ConfirmPickupSpot(
            initialPosition: start,
            initialAddress: 'Klockarvägen 37',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomGoogleMap), findsOneWidget);
      return result;
    }

    CustomGoogleMap map(WidgetTester tester) =>
        tester.widget<CustomGoogleMap>(find.byType(CustomGoogleMap));

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(
        find.widgetWithText(FilledButton, 'Confirm pickup'),
        warnIfMissed: false,
      );
    }

    testWidgets('while the pin is still moving', (tester) async {
      final result = await open(tester);
      map(tester).onCameraMoveStarted?.call();
      map(tester).onCameraMove!(const CameraPosition(target: moved, zoom: 16));
      await confirm(tester);
      await tester.pumpAndSettle();
      final picked = await result;
      expect(picked, isNotNull);
      expect(picked!.position, moved);
      expect(picked.address, isNot('Klockarvägen 37'));
      expect(picked.address, startsWith('Dropped pin'));
    });

    testWidgets('while its street lookup is pending', (tester) async {
      final result = await open(tester);
      map(tester).onCameraMoveStarted?.call();
      map(tester).onCameraMove!(const CameraPosition(target: moved, zoom: 16));
      map(tester).onCameraIdle!();
      await confirm(tester);
      await tester.pumpAndSettle();
      final picked = await result;
      expect(picked!.position, moved);
      expect(picked.address, isNot('Klockarvägen 37'));
      // Let the street lookup's request timer run out.
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('an untouched pin keeps its address', (tester) async {
      final result = await open(tester);
      await confirm(tester);
      await tester.pumpAndSettle();
      final picked = await result;
      expect(picked!.address, 'Klockarvägen 37');
    });
  });
}
