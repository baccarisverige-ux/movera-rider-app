import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

/// Moving the pin on Set location prices the ride again from that point.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const start = LatLng(59.3293, 18.0686);
  const moved = LatLng(59.3340, 18.0686);

  Future<void> open(
    WidgetTester tester, {
    required Future<SetPickupFare?> Function(LatLng pin) onRequote,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SetPickupPage.open(
                context,
                initialPosition: start,
                initialAddress: 'Klockarvägen 37',
                destinationAddress: 'Arlanda',
                destinationPosition: const LatLng(59.6519, 17.9186),
                ride: const SetPickupRide(
                  name: 'Movera',
                  image: 'missing.png',
                  seats: 4,
                  etaMin: 5,
                  tripMinutes: 40,
                ),
                fare: const SetPickupFare(totalKr: 259),
                payment: const SetPickupPayment(
                  brand: 'cash',
                  name: 'Pay in car',
                  detail: '',
                ),
                brandMark: (_) => const SizedBox(),
                onRequote: onRequote,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('set-pickup-map')), findsOneWidget);
  }

  /// The rider drags the map so the pin lands on [target]: the map reports
  /// the move, the new camera and then that it settled.
  Future<void> dragPinTo(WidgetTester tester, LatLng target) async {
    final map = tester.widget<CustomGoogleMap>(
      find.byKey(const ValueKey('set-pickup-map')),
    );
    map.onCameraMoveStarted!();
    map.onCameraMove!(CameraPosition(target: target, zoom: 16));
    map.onCameraIdle!();
    await tester.pump();
  }

  /// Lets the pin drop and the address lookup (8 s timeout) finish before
  /// the test ends.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
  }

  testWidgets('a moved pin asks for a new price and shows it', (tester) async {
    final pins = <LatLng>[];
    final answer = Completer<SetPickupFare?>();
    await open(
      tester,
      onRequote: (pin) {
        pins.add(pin);
        return answer.future;
      },
    );
    expect(find.text('kr 259'), findsOneWidget);
    expect(find.byKey(const ValueKey('set-pickup-requoting')), findsNothing);

    await dragPinTo(tester, moved);
    expect(pins, hasLength(1));
    expect(pins.single.latitude, isNot(closeTo(start.latitude, 0.0001)));
    expect(find.text('Updating price…'), findsOneWidget);
    expect(find.byKey(const ValueKey('set-pickup-requoting')), findsOneWidget);
    // Still bookable while the price refreshes.
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('set-pickup-confirm')),
    );
    expect(confirm.onPressed, isNotNull);

    answer.complete(
      const SetPickupFare(totalKr: 301, discountKr: 40, promotionPercent: 12),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('set-pickup-requoting')), findsNothing);
    expect(find.text('kr 259'), findsNothing);
    expect(find.text('kr 301'), findsOneWidget);
    expect(find.text('kr 341'), findsOneWidget);
    expect(find.text('Promotion 12%'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('a late answer for an earlier pin is ignored', (tester) async {
    final answers = <Completer<SetPickupFare?>>[];
    await open(
      tester,
      onRequote: (_) {
        final c = Completer<SetPickupFare?>();
        answers.add(c);
        return c.future;
      },
    );
    await dragPinTo(tester, moved);
    await dragPinTo(tester, const LatLng(59.3400, 18.0686));
    expect(answers, hasLength(2));

    answers[1].complete(const SetPickupFare(totalKr: 310));
    await tester.pump();
    await tester.pump();
    expect(find.text('kr 310'), findsOneWidget);
    expect(find.byKey(const ValueKey('set-pickup-requoting')), findsNothing);

    answers[0].complete(const SetPickupFare(totalKr: 280));
    await tester.pump();
    await tester.pump();
    expect(find.text('kr 310'), findsOneWidget);
    expect(find.text('kr 280'), findsNothing);
    await settle(tester);
  });

  testWidgets('a failed quote keeps the price shown', (tester) async {
    await open(tester, onRequote: (_) async => throw StateError('offline'));
    await dragPinTo(tester, moved);
    await tester.pump();
    await tester.pump();
    expect(find.text('kr 259'), findsOneWidget);
    expect(find.byKey(const ValueKey('set-pickup-requoting')), findsNothing);
    await settle(tester);
  });

  testWidgets('the pin staying put asks for nothing', (tester) async {
    var calls = 0;
    await open(
      tester,
      onRequote: (_) async {
        calls++;
        return null;
      },
    );
    final map = tester.widget<CustomGoogleMap>(
      find.byKey(const ValueKey('set-pickup-map')),
    );
    // A wobble that ends where it began.
    map.onCameraMoveStarted!();
    map.onCameraIdle!();
    await tester.pump();
    expect(calls, 0);
    await settle(tester);
  });

  testWidgets('Set pickup stays flat: a pinch never tilts the pin map', (
    tester,
  ) async {
    final pins = <LatLng>[];
    await open(
      tester,
      onRequote: (pin) async {
        pins.add(pin);
        return null;
      },
    );
    final pickupMap = find.byKey(const ValueKey('set-pickup-map'));
    expect(tester.widget<CustomGoogleMap>(pickupMap).tiltWithZoom, isFalse);
    final map = tester.widget<GoogleMap>(
      find.descendant(of: pickupMap, matching: find.byType(GoogleMap)),
    );
    final camera = _CameraLog();
    map.onMapCreated!(camera);
    // Pinch in to 17.5 and let go: the pin's ground point is still read from
    // the flat camera centre and no tilt ease is sent.
    map.onCameraMoveStarted!();
    map.onCameraMove!(const CameraPosition(target: moved, zoom: 17.5));
    map.onCameraIdle!();
    await tester.pump();
    expect(camera.updates, isEmpty);
    expect(pins, hasLength(1));
    expect(pins.single.latitude, greaterThan(moved.latitude));
    expect(pins.single.latitude - moved.latitude, lessThan(0.002));
    expect(pins.single.longitude, closeTo(moved.longitude, 1e-9));
    await settle(tester);
  });
}

class _CameraLog extends Fake implements GoogleMapController {
  final List<Object> updates = [];

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate, {Duration? duration}) {
    updates.add(cameraUpdate.toJson());
    return Future<void>.value();
  }

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate) {
    updates.add(cameraUpdate.toJson());
    return Future<void>.value();
  }

  @override
  Future<String?> getStyleError() async => null;
}
