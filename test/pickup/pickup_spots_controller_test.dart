import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/application/pickup_spots_controller.dart';
import 'package:movera_rider/features/pickup/domain/pickup_spot.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore implements PreviousPickupsStore {
  List<PreviousPickup> items = const [];

  @override
  Future<List<PreviousPickup>> read() async => items;

  @override
  Future<void> write(List<PreviousPickup> pickups) async => items = pickups;
}

void main() {
  const at = LatLng(59.2390, 17.8450);
  const address = 'Klockarvägen 37, Huddinge';

  test(
    'entrances, then parking, placed deterministically around the point',
    () async {
      final controller = PickupSpotsController(store: _MemoryStore());
      final spots = await controller.forAddress(at: at, address: address);
      expect(spots.map((s) => s.title), [
        'Main entrance',
        'Side entrance',
        'Parking',
      ]);
      expect(spots.map((s) => s.kind), [
        PickupSpotKind.entrance,
        PickupSpotKind.entrance,
        PickupSpotKind.parking,
      ]);
      expect(spots[2].subtitle, 'Short walk');
      // ~25 m north, ~30 m south, ~60 m east.
      expect(pickupSpotDistanceM(at, spots[0].position), closeTo(25, 0.5));
      expect(spots[0].position.latitude, greaterThan(at.latitude));
      expect(pickupSpotDistanceM(at, spots[1].position), closeTo(30, 0.5));
      expect(spots[1].position.latitude, lessThan(at.latitude));
      expect(pickupSpotDistanceM(at, spots[2].position), closeTo(60, 0.5));
      expect(spots[2].position.longitude, greaterThan(at.longitude));
      // Same point, same spots.
      final again = await controller.forAddress(at: at, address: address);
      expect(again.map((s) => s.position), spots.map((s) => s.position));
    },
  );

  test('Near Home only when Home is within 300 m', () async {
    final controller = PickupSpotsController(store: _MemoryStore());
    final near = await controller.forAddress(
      at: at,
      address: address,
      home: pickupSpotOffset(at, northM: 200),
    );
    expect(near.last.title, 'Near Home');
    expect(near.last.kind, PickupSpotKind.home);
    expect(near.last.position, pickupSpotOffset(at, northM: 200));

    final far = await controller.forAddress(
      at: at,
      address: address,
      home: pickupSpotOffset(at, northM: 400),
    );
    expect(far.any((s) => s.kind == PickupSpotKind.home), isFalse);

    final none = await controller.forAddress(at: at, address: address);
    expect(none.any((s) => s.kind == PickupSpotKind.home), isFalse);
  });

  test('previously used spots come first, at most two, newest first', () async {
    final store = _MemoryStore();
    final controller = PickupSpotsController(store: store);
    final a = pickupSpotOffset(at, eastM: -40);
    final b = pickupSpotOffset(at, northM: 70);
    final c = pickupSpotOffset(at, eastM: 100);
    await controller.remember(
      position: a,
      address: 'Klockarvägen 37',
      at: DateTime(2026, 1, 1),
    );
    await controller.remember(
      position: b,
      address: 'Klockarvägen 37 – Side gate',
      at: DateTime(2026, 1, 2),
    );
    await controller.remember(
      position: c,
      address: 'Klockarvägen 39',
      at: DateTime(2026, 1, 3),
    );

    final spots = await controller.forAddress(
      at: at,
      address: address,
      home: pickupSpotOffset(at, northM: 100),
    );
    expect(spots.length, 6);
    expect(spots.map((s) => s.title), [
      'Previously used',
      'Previously used',
      'Main entrance',
      'Side entrance',
      'Parking',
      'Near Home',
    ]);
    expect(spots[0].position, c);
    expect(spots[0].subtitle, 'Klockarvägen 39');
    expect(spots[1].position, b);
    expect(spots[1].subtitle, 'Side gate');
  });

  test(
    'a previous pickup under the pin or on a named spot is not repeated',
    () async {
      final store = _MemoryStore();
      final controller = PickupSpotsController(store: store);
      await controller.remember(position: at, address: 'Klockarvägen 37');
      await controller.remember(
        position: pickupSpotOffset(at, northM: 25),
        address: 'Klockarvägen 37 – Main entrance',
      );
      await controller.remember(
        position: pickupSpotOffset(at, northM: 900),
        address: 'Somewhere else',
      );
      final spots = await controller.forAddress(at: at, address: address);
      expect(spots.where((s) => s.kind == PickupSpotKind.previous), isEmpty);
      expect(spots.length, 3);
    },
  );

  test(
    'remember keeps the last five, newest first, without duplicates',
    () async {
      final store = _MemoryStore();
      final controller = PickupSpotsController(store: store);
      for (var i = 0; i < 7; i++) {
        await controller.remember(
          position: pickupSpotOffset(at, eastM: 30.0 * i),
          address: 'Stop $i',
          at: DateTime(2026, 1, 1 + i),
        );
      }
      expect(store.items.length, 5);
      expect(store.items.first.address, 'Stop 6');
      expect(store.items.last.address, 'Stop 2');
      // The same spot again moves to the top instead of doubling.
      await controller.remember(
        position: pickupSpotOffset(at, eastM: 30.0 * 4),
        address: 'Stop 4 again',
        at: DateTime(2026, 2, 1),
      );
      expect(store.items.length, 5);
      expect(store.items.first.address, 'Stop 4 again');
      expect(
        store.items.where((p) => p.address.startsWith('Stop 4')).length,
        1,
      );
    },
  );

  test('confirmed pickups persist in SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final first = PickupSpotsController();
    final spot = pickupSpotOffset(at, eastM: -50);
    await first.remember(
      position: spot,
      address: 'Klockarvägen 37 – Back yard',
    );

    final second = PickupSpotsController();
    final spots = await second.forAddress(at: at, address: address);
    expect(spots.first.kind, PickupSpotKind.previous);
    expect(spots.first.title, 'Previously used');
    expect(spots.first.subtitle, 'Back yard');
    expect(spots.first.position.latitude, closeTo(spot.latitude, 1e-9));
    expect(spots.first.position.longitude, closeTo(spot.longitude, 1e-9));
  });

  test('labels: street – spot; the street drops the town and an old spot', () {
    const spot = PickupSpot(
      id: 'entrance-main',
      title: 'Main entrance',
      subtitle: '',
      kind: PickupSpotKind.entrance,
      position: at,
    );
    expect(
      pickupSpotLabel('Klockarvägen 37', spot),
      'Klockarvägen 37 – Main entrance',
    );
    expect(
      pickupSpotLabel('Klockarvägen 37, Huddinge', spot),
      'Klockarvägen 37 – Main entrance',
    );
    expect(
      pickupSpotLabel('Klockarvägen 37 – Parking', spot),
      'Klockarvägen 37 – Main entrance',
    );
    expect(pickupSpotLabel('  ', spot), 'Main entrance');
    expect(
      pickupSpotStreet('Klockarvägen 37 – Parking, Huddinge'),
      'Klockarvägen 37',
    );
  });
}
