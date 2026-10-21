import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const start = LatLng(59.3293, 18.0686);
  const moved = LatLng(59.3340, 18.0686);

  Future<Future<SetPickupResult?>> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    SetPickupFare fare = const SetPickupFare(totalKr: 259),
    Future<SetPickupFare?> Function(LatLng pin)? onRequote,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    late Future<SetPickupResult?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => result = SetPickupPage.open(
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
                fare: fare,
                payment: const SetPickupPayment(
                  brand: 'cash',
                  name: 'Cash',
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
    return result;
  }

  CustomGoogleMap map(WidgetTester tester) => tester.widget<CustomGoogleMap>(
    find.byKey(const ValueKey('set-pickup-map')),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
  }

  testWidgets('rider-u139: the pickup address sheet sits on the keyboard', (
    tester,
  ) async {
    await open(tester, size: const Size(360, 640));
    await tester.tap(find.text('Klockarvägen 37').first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    final field = find.widgetWithText(TextField, 'Search address');
    expect(field, findsOneWidget);
    final rect = tester.getRect(field);
    expect(rect.bottom, lessThanOrEqualTo(640 - 280));
    // Not floating a second keyboard height above the keyboard.
    expect(rect.bottom, greaterThan(640 - 280 - 80));
    await tester.enterText(field, 'Kungsgatan 1');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
  });

  testWidgets('rider-u140: Confirm during a glide waits for the pin to '
      'settle and books its own street and fare', (tester) async {
    final quotes = <LatLng>[];
    final result = await open(
      tester,
      onRequote: (pin) async {
        quotes.add(pin);
        return const SetPickupFare(totalKr: 301);
      },
    );
    // A fling: the finger is up, the camera still slides.
    map(tester).onCameraMoveStarted!();
    map(tester).onCameraMove!(const CameraPosition(target: moved, zoom: 16));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    // The glide ends.
    map(tester).onCameraIdle!();
    await settle(tester);
    final picked = await result;
    expect(picked, isNotNull);
    expect(picked!.address, isNot('Klockarvägen 37'));
    expect(quotes, isNotEmpty);
    expect(picked.fareTotalKr, 301);
    expect(picked.position.latitude, closeTo(quotes.last.latitude, 1e-9));
  });

  testWidgets('rider-u141: the open sheet keeps Confirm on screen at '
      '375x667, with a promotion and a wallet part', (tester) async {
    await open(
      tester,
      size: const Size(375, 667),
      fare: const SetPickupFare(
        totalKr: 259,
        discountKr: 40,
        promotionPercent: 12,
        walletKr: 50,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('set-pickup-handle')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final sheet = tester.getRect(
      find.byKey(const ValueKey('set-pickup-sheet')),
    );
    final confirm = tester.getRect(
      find.byKey(const ValueKey('set-pickup-confirm')),
    );
    expect(confirm.bottom, lessThanOrEqualTo(sheet.bottom));
    expect(confirm.bottom, lessThanOrEqualTo(667));
    await tester.tap(find.byKey(const ValueKey('set-pickup-confirm')));
    await settle(tester);
  });
}
