import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/application/pickup_spots_controller.dart';
import 'package:movera_rider/features/pickup/domain/pickup_spot.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';

import 'tree_snapshot.dart';

// Rule 25 split (2026-11-07): Set pickup split into part files with no
// behaviour change. Each snapshot was written before the split and must
// match after it.

class _MemoryStore implements PreviousPickupsStore {
  List<PreviousPickup> items = const [];

  @override
  Future<List<PreviousPickup>> read() async => items;

  @override
  Future<void> write(List<PreviousPickup> pickups) async => items = pickups;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> openPage(
    WidgetTester tester, {
    required SetPickupFare fare,
    LatLng? home,
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
                initialPosition: const LatLng(59.3293, 18.0686),
                initialAddress: 'Klockarvägen 37',
                destinationAddress: 'Alby Centrum, Norsborg',
                destinationPosition: const LatLng(59.2390, 17.8450),
                ride: const SetPickupRide(
                  name: 'Comfort',
                  image: 'missing.png',
                  seats: 4,
                  etaMin: 11,
                  tripMinutes: 22,
                ),
                fare: fare,
                payment: const SetPickupPayment(
                  brand: 'cash',
                  name: 'Cash',
                  detail: 'Pay the driver in cash',
                ),
                brandMark: (_) => const Icon(Icons.directions_car),
                onChangePayment: () async => null,
                spotsController: PickupSpotsController(store: _MemoryStore()),
                home: home,
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
  }

  testWidgets('set pickup snapshot: promotion fare, spots, bags, payment', (
    tester,
  ) async {
    await openPage(
      tester,
      fare: const SetPickupFare(
        totalKr: 237,
        discountKr: 102,
        promotionPercent: 30,
      ),
    );
    expect(find.byType(SetPickupPage), findsOneWidget);
    expectTreeSnapshot(tester, 'rider_set_pickup');
  });

  testWidgets('set pickup snapshot: wallet part-payment near Home', (
    tester,
  ) async {
    await openPage(
      tester,
      fare: const SetPickupFare(totalKr: 237, walletKr: 50),
      home: const LatLng(59.3295, 18.0688),
    );
    expect(find.byType(SetPickupPage), findsOneWidget);
    expectTreeSnapshot(tester, 'rider_set_pickup_wallet');
  });
}
