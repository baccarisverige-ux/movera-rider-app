import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/finding_driver/presentation/ride_details_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-20 (approved mockup, coordinator gap): the same Ride
/// details sheet ("…" → price, pencils, +) while the driver is coming and
/// during the trip. The pickup pencil only while the pickup may still move
/// (searching, or the ≤ maxPickupMoveMeters move before arrival); the
/// destination pencil and "+" in every phase.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('which pencils each phase shows', () {
    // Driver coming, before arrival: pickup move + route.
    expect(WaitingForDriver.detailsPencils(pickupEditable: true), (
      pickup: true,
      route: true,
    ));
    // Driver arrived or on the trip: route only.
    expect(WaitingForDriver.detailsPencils(pickupEditable: false), (
      pickup: false,
      route: true,
    ));
  });

  for (final phase in ['driver coming', 'on the trip']) {
    testWidgets(
      '$phase: "…" opens Ride details with price and the right pencils',
      (tester) async {
        final pencils = WaitingForDriver.detailsPencils(
          pickupEditable: phase == 'driver coming',
        );
        final taps = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => RideDetailsSheet.open(
                    context,
                    pickupAddress: 'Klockarvägen 37',
                    destinationAddress: 'Arlanda Airport',
                    rideType: 'Movera',
                    price: 600,
                    currency: 'SEK',
                    paymentMethod: 'Cash',
                    notes: const RideNotes(),
                    allowCancel: phase == 'driver coming',
                    onCancelTrip: (_) => taps.add('cancel'),
                    onEditPickup: pencils.pickup
                        ? (_) => taps.add('pickup')
                        : null,
                    onEditDestination: (_) => taps.add('destination'),
                    onAddStop: (_) => taps.add('stop'),
                  ),
                  child: const Text('…'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('…'));
        await tester.pumpAndSettle();
        expect(find.textContaining('600'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('ride-details-edit-pickup')),
          pencils.pickup ? findsOneWidget : findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('ride-details-edit-destination')),
        );
        await tester.pumpAndSettle();
        expect(taps, ['destination']);
      },
    );
  }
}
