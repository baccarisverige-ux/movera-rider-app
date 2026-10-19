import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/application/pickup_spots_controller.dart';
import 'package:movera_rider/features/pickup/domain/pickup_spot.dart';
import 'package:movera_rider/features/pickup/presentation/set_pickup_page.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';

class _MemoryStore implements PreviousPickupsStore {
  List<PreviousPickup> items = const [];

  @override
  Future<List<PreviousPickup>> read() async => items;

  @override
  Future<void> write(List<PreviousPickup> pickups) async => items = pickups;
}

class _ResultBox {
  SetPickupResult? value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<SetPickupResult?> Function() openPage(
    WidgetTester tester, {
    SetPickupFare fare = const SetPickupFare(totalKr: 237),
    bool fallback = false,
    LatLng? home,
    _MemoryStore? store,
    _ResultBox? box,
  }) {
    final spotStore = store ?? _MemoryStore();
    SetPickupResult? result;
    var done = false;
    return () async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await SetPickupPage.open(
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
                      name: 'Pay in car',
                      detail: 'Cash, card or Swish to the driver',
                    ),
                    brandMark: (_) => const Icon(Icons.directions_car),
                    onChangePayment: () async => null,
                    spotsController: PickupSpotsController(store: spotStore),
                    home: home,
                    positionIsFallback: fallback,
                  );
                  box?.value = result;
                  done = true;
                },
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
      return done ? result : null;
    };
  }

  testWidgets('shows the ride, pickup, spots, bags, price, payment and CTA', (
    tester,
  ) async {
    await openPage(
      tester,
      fare: const SetPickupFare(totalKr: 237, discountKr: 102, promotionPercent: 30),
    )();
    expect(find.byType(SetPickupPage), findsOneWidget);
    expect(find.text('Alby Centrum, Norsborg'), findsOneWidget);
    expect(find.text('Comfort'), findsOneWidget);
    expect(find.textContaining('Driver arrives in 11 min'), findsOneWidget);
    expect(find.text('Pickup spot'), findsOneWidget);
    expect(find.text('Klockarvägen 37'), findsOneWidget);
    expect(find.text('Your current location'), findsOneWidget);
    expect(find.text('Main entrance'), findsOneWidget);
    expect(find.text('Side entrance'), findsOneWidget);
    expect(find.text('Parking'), findsOneWidget);
    expect(find.text('Near Home'), findsNothing);
    expect(find.text('On map'), findsOneWidget);
    expect(find.text('Bags?'), findsOneWidget);
    expect(find.text('Ride price'), findsOneWidget);
    expect(find.text('339 kr'), findsOneWidget);
    expect(find.text('Promotion 30%'), findsOneWidget);
    expect(find.text('-102 kr'), findsOneWidget);
    expect(find.text('237 kr'), findsOneWidget);
    expect(find.text('Pay in car'), findsOneWidget);
    expect(find.text('Confirm and search'), findsOneWidget);
    expect(find.byKey(const ValueKey('set-pickup-pin')), findsOneWidget);
  });

  testWidgets('without a promotion only the total is shown', (tester) async {
    await openPage(tester)();
    expect(find.text('Ride price'), findsNothing);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('237 kr'), findsOneWidget);
  });

  testWidgets('confirm returns the pickup and the chosen bags', (tester) async {
    SetPickupResult? result;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await SetPickupPage.open(
                  context,
                  initialPosition: const LatLng(59.3293, 18.0686),
                  initialAddress: 'Klockarvägen 37',
                  destinationAddress: 'Odenplan',
                  destinationPosition: const LatLng(59.3429, 18.0496),
                  ride: const SetPickupRide(
                    name: 'Comfort',
                    image: 'missing.png',
                    seats: 4,
                    etaMin: 6,
                    tripMinutes: 12,
                  ),
                  fare: const SetPickupFare(totalKr: 199),
                  payment: const SetPickupPayment(
                    brand: 'cash',
                    name: 'Pay in car',
                    detail: '',
                  ),
                  brandMark: (_) => const SizedBox(),
                  spotsController: PickupSpotsController(store: _MemoryStore()),
                );
              },
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
    // Opens short: the bags sit in the details, one tap on the handle away.
    await tester.tap(find.byKey(const ValueKey('set-pickup-handle')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('3+'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Confirm and search'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsNothing);
    expect(result, isNotNull);
    expect(result!.address, 'Klockarvägen 37');
    expect(result!.bagLevel, 2);
    expect(result!.position, const LatLng(59.3293, 18.0686));
  });

  testWidgets('a fallback map point cannot be confirmed', (tester) async {
    await openPage(tester, fallback: true)();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('set-pickup-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('opens short; the handle shows the details and hides them', (
    tester,
  ) async {
    await openPage(tester)();
    expect(find.text('Bags?').hitTestable(), findsNothing);
    expect(find.text('Confirm and search').hitTestable(), findsOneWidget);
    expect(find.text('Klockarvägen 37').hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('set-pickup-handle')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Bags?').hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('set-pickup-handle')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Bags?').hitTestable(), findsNothing);
  });

  testWidgets('dragging the sheet up brings the details in', (tester) async {
    await openPage(tester)();
    await tester.drag(find.text('Pickup spot'), const Offset(0, -320));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Bags?').hitTestable(), findsOneWidget);
  });

  testWidgets('the short sheet has a bags chip that cycles the level', (
    tester,
  ) async {
    await openPage(tester)();
    final chip = find.byKey(const ValueKey('set-pickup-bags-chip'));
    expect(chip.hitTestable(), findsOneWidget);
    expect(find.text('Bags'), findsOneWidget);
    await tester.tap(chip);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('1–2 bags'), findsOneWidget);
    await tester.tap(chip);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('3+ bags'), findsOneWidget);
    // Opening the sheet hides the chip; the full Bags row takes over.
    await tester.tap(find.byKey(const ValueKey('set-pickup-handle')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(chip.hitTestable(), findsNothing);
    expect(find.text('Bags?').hitTestable(), findsOneWidget);
  });

  testWidgets('spot chips show for the address; Near Home only close to Home', (
    tester,
  ) async {
    await openPage(tester, home: const LatLng(59.3300, 18.0686))();
    final row = find.byKey(const ValueKey('set-pickup-spots'));
    expect(row, findsOneWidget);
    expect(find.text('Main entrance').hitTestable(), findsOneWidget);
    // The row scrolls sideways; later chips come into view.
    for (final label in ['Side entrance', 'Parking', 'Near Home', 'On map']) {
      await tester.ensureVisible(find.text(label));
      await tester.pump();
      expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
    }
    expect(find.byIcon(Icons.door_front_door_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.local_parking_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
  });

  testWidgets('tapping a spot chip renames the pickup, fills the chip and '
      'confirms with that label', (tester) async {
    final store = _MemoryStore();
    final box = _ResultBox();
    await openPage(tester, store: store, box: box)();
    expect(find.text('Klockarvägen 37'), findsOneWidget);

    await tester.tap(find.text('Main entrance'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Klockarvägen 37 – Main entrance'), findsOneWidget);
    expect(find.text('Front of the building'), findsOneWidget);
    final chipKey = const ValueKey('set-pickup-spot-entrance-main');
    final chip = tester.widget<Material>(
      find.descendant(of: find.byKey(chipKey), matching: find.byType(Material)).first,
    );
    expect(chip.color, const Color(0xFF11181D));
    final parkingChip = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const ValueKey('set-pickup-spot-parking')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(parkingChip.color, isNot(const Color(0xFF11181D)));

    // Another chip takes over.
    await tester.ensureVisible(find.text('Parking'));
    await tester.pump();
    await tester.tap(find.text('Parking'));
    await tester.pump(const Duration(milliseconds: 300));
    // The old label fades out over two frames.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Klockarvägen 37 – Parking'), findsOneWidget);
    expect(find.text('Short walk'), findsOneWidget);
    expect(find.text('Klockarvägen 37 – Main entrance'), findsNothing);

    await tester.tap(find.text('Confirm and search'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SetPickupPage), findsNothing);
    // The spot itself is the pickup point, ~60 m east of the address.
    final result = box.value;
    expect(result, isNotNull);
    expect(result!.address, 'Klockarvägen 37 – Parking');
    expect(result.position.longitude, greaterThan(18.0686));
    expect(result.position.latitude, closeTo(59.3293, 1e-6));
    // Confirming remembers the spot for next time.
    expect(store.items.single.address, 'Klockarvägen 37 – Parking');
    expect(store.items.single.position, result.position);
  });

  testWidgets('a remembered pickup comes back as Previously used, first', (
    tester,
  ) async {
    final store = _MemoryStore()
      ..items = [
        PreviousPickup(
          position: const LatLng(59.3293, 18.0693),
          address: 'Klockarvägen 37 – Courtyard',
          savedAt: DateTime(2026, 1, 1),
        ),
      ];
    await openPage(tester, store: store)();
    expect(find.text('Previously used'), findsOneWidget);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    final row = tester.widget<Row>(
      find
          .descendant(
            of: find.byKey(const ValueKey('set-pickup-spots')),
            matching: find.byType(Row),
          )
          .first,
    );
    final firstChip = row.children.first;
    expect(
      find.descendant(of: find.byWidget(firstChip), matching: find.text('Previously used')),
      findsOneWidget,
    );
    await tester.tap(find.text('Previously used'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Klockarvägen 37 – Previously used'), findsOneWidget);
    expect(find.text('Courtyard'), findsOneWidget);
  });

  test('bags are kept on the ride notes', () {
    final notes = RideNotes.empty.withBagLevel(2);
    expect(notes.bagLevel, 2);
    expect(notes.toJson()['bagsCount'], '3+');
    expect(RideNotes.fromJson(notes.toJson()).bagLevel, 2);
    expect(RideNotes.empty.withBagLevel(1).selected, ['Bags']);
    expect(RideNotes.empty.withBagLevel(0).bags, isFalse);
  });
}
