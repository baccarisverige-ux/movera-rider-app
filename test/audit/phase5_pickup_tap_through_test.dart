import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/application/pickup_spots_controller.dart';
import 'package:movera_rider/features/pickup/domain/pickup_spot.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';

class _MemoryStore implements PreviousPickupsStore {
  List<PreviousPickup> items = const [];

  @override
  Future<List<PreviousPickup>> read() async => items;

  @override
  Future<void> write(List<PreviousPickup> pickups) async => items = pickups;
}

/// Audit Phase 5, P5-R6: on the live build a double tap on "Select Movera"
/// booked a ride. The second tap landed on Set pickup's "Confirm and
/// search", which sits where "Select Movera" was, while that screen was
/// still sliding in (measured in Chromium: taps 200 ms and 350 ms apart each
/// made one POST /trips). A tap that arrives before the screen has finished
/// opening is not the rider confirming this pickup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Confirm and search ignores a tap while Set pickup is still '
      'opening, and works once it is open', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var results = 0;
    SetPickupResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final r = await SetPickupPage.open(
                  context,
                  initialPosition: const LatLng(59.3293, 18.0686),
                  initialAddress: 'Klockarvägen 37',
                  destinationAddress: 'Odenplan',
                  destinationPosition: const LatLng(59.3429, 18.0496),
                  ride: const SetPickupRide(
                    name: 'Movera',
                    image: 'missing.png',
                    seats: 4,
                    etaMin: 6,
                    tripMinutes: 12,
                  ),
                  fare: const SetPickupFare(totalKr: 75),
                  payment: const SetPickupPayment(
                    brand: 'cash',
                    name: 'Cash',
                    detail: 'Pay the driver in cash',
                  ),
                  brandMark: (_) => const Icon(Icons.directions_car),
                  spotsController: PickupSpotsController(store: _MemoryStore()),
                );
                if (r != null) {
                  results += 1;
                  result = r;
                }
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final confirm = find.byKey(const ValueKey('set-pickup-confirm'));
    expect(confirm, findsOneWidget);

    // Still sliding in: the second tap of a double tap.
    await tester.tap(confirm, warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsOneWidget);
    expect(results, 0);

    // Open: the rider's own tap confirms, once.
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsNothing);
    expect(results, 1);
    expect(result?.address, isNotEmpty);
  });
}
