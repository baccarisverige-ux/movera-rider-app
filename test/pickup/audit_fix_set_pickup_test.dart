import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const start = LatLng(59.3293, 18.0686);

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
}
