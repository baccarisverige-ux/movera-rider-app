import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/application/pickup_spots_controller.dart';
import 'package:movera_rider/features/pickup/domain/pickup_spot.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';

import '../../integration_test/staging/tap_ready.dart';

class _MemoryStore implements PreviousPickupsStore {
  List<PreviousPickup> items = const [];

  @override
  Future<List<PreviousPickup>> read() async => items;

  @override
  Future<void> write(List<PreviousPickup> pickups) async => items = pickups;
}

/// G31 phone run 1, BOOK FAIL ("POST /trips=[] quotes=[201]"): the run's
/// wait for "Confirm and search" was "hit-testable and enabled"
/// (trip_book.dart before this fix). That is already true while Set pickup
/// slides in, and the app ignores a tap then on purpose (P5-R6,
/// set_pickup_page.dart `_confirm`). So the run could tap a Confirm the app
/// never took, then wait 60 s for Finding with no booking sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the old wait says "ready" while the app still ignores the '
      'tap; readyToTap waits until it is taken', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var results = 0;
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
                if (r != null) results += 1;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final confirm = find.byKey(const ValueKey('set-pickup-confirm'));

    // The run-1 wait: true already.
    final oldWait =
        tester.any(confirm.hitTestable()) &&
        (tester.widget(confirm) as FilledButton).onPressed != null;
    expect(oldWait, isTrue);
    expect(readyToTap(tester, confirm), isFalse);

    // A tap now is not taken (what run 1 saw: no booking).
    await tester.tap(confirm, warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(results, 0);
    expect(find.byType(SetPickupPage), findsOneWidget);

    // Once readyToTap says so, the tap is taken.
    expect(readyToTap(tester, confirm), isTrue);
    await tester.tap(confirm);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(results, 1);
  });
}
