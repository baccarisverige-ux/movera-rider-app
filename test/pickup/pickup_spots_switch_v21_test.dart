// Contract v0.18.115 (BQ-V21, contract.json#pickupSpots; owner full-audit
// Q6 2026-11-02 "Keep as 'approximate'" => admin on/off per zone, default
// on; Rules decisions/rider-g4-pickup.md:7): the zone's
// `booking.pickupSpots.on` hides or shows the approximate entrance chips.
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/pickup/application/pickup_spots_controller.dart';
import 'package:movera_rider/features/pickup/domain/pickup_spot.dart';

class _MemoryStore implements PreviousPickupsStore {
  _MemoryStore([this.items = const []]);

  List<PreviousPickup> items;

  @override
  Future<List<PreviousPickup>> read() async => items;

  @override
  Future<void> write(List<PreviousPickup> pickups) async => items = pickups;
}

class _Repo implements RiderConfigRepository {
  _Repo(this.config);

  final RiderAppConfig config;
  final asked = <String>[];

  @override
  Future<RiderAppConfig> current() async => config;

  @override
  Future<RiderAppConfig> forZone(String zoneId) async {
    asked.add(zoneId);
    return config;
  }
}

Map<String, Object?> _doc([Map<String, Object?>? booking]) => {
  'version': 3,
  'zoneId': 'Z001',
  'currency': 'SEK',
  'booking': ?booking,
};

void main() {
  const at = LatLng(59.2390, 17.8450);
  const home = LatLng(59.2392, 17.8452);
  const address = 'Klockarvägen 37, Huddinge';
  const entranceIds = ['entrance-main', 'entrance-side', 'parking'];

  test(
    'booking.pickupSpots.on is read; missing or bad (older server) = on',
    () {
      bool on(Map<String, Object?> doc) =>
          RiderAppConfig.fromJson(doc)!.pickupSpotsOn;
      expect(
        on(
          _doc({
            'maxStops': 3,
            'pickupSpots': {'on': false},
          }),
        ),
        isFalse,
      );
      expect(
        on(
          _doc({
            'pickupSpots': {'on': true},
          }),
        ),
        isTrue,
      );
      expect(on(_doc({'maxStops': 3})), isTrue, reason: 'older server');
      expect(on(_doc()), isTrue, reason: 'no booking at all');
      expect(on(_doc({'pickupSpots': 'off'})), isTrue, reason: 'bad shape');
      expect(
        on(
          _doc({
            'pickupSpots': {'on': 'no'},
          }),
        ),
        isTrue,
        reason: 'bad value',
      );
    },
  );

  test('off: no entrance chips; Near Home and Previously used stay', () async {
    final store = _MemoryStore([
      PreviousPickup(
        position: pickupSpotOffset(at, eastM: -80),
        address: 'Klockarvägen 41, Huddinge',
        savedAt: DateTime.utc(2026, 11, 15),
      ),
    ]);
    final controller = PickupSpotsController(
      store: store,
      entrancesOn: (_) async => false,
    );
    final spots = await controller.forAddress(
      at: at,
      address: address,
      home: home,
    );
    expect(spots.map((s) => s.id), ['previous-0', 'home']);
    expect(
      spots.map((s) => s.kind),
      isNot(contains(anyOf(PickupSpotKind.entrance, PickupSpotKind.parking))),
    );
  });

  test(
    'on, unset or failing: the entrance chips show (owner default on)',
    () async {
      for (final entrancesOn in <Future<bool> Function(LatLng)?>[
        (_) async => true,
        null,
        (_) async => throw StateError('config unreadable'),
      ]) {
        final spots = await PickupSpotsController(
          store: _MemoryStore(),
          entrancesOn: entrancesOn,
        ).forAddress(at: at, address: address);
        expect(spots.map((s) => s.id), entranceIds);
      }
    },
  );

  test('the switch comes from the rider config of the pickup zone', () async {
    final off = _Repo(
      RiderAppConfig.fromJson(
        _doc({
          'pickupSpots': {'on': false},
        }),
      )!,
    );
    final controller = PickupSpotsController(
      store: _MemoryStore(),
      entrancesOn: PickupSpotsController.entrancesOnFrom(off),
    );
    expect(await controller.forAddress(at: at, address: address), isEmpty);
    expect(off.asked, isNotEmpty);
    final older = _Repo(RiderAppConfig.fromJson(_doc({'maxStops': 3}))!);
    final shown = await PickupSpotsController(
      store: _MemoryStore(),
      entrancesOn: PickupSpotsController.entrancesOnFrom(older),
    ).forAddress(at: at, address: address);
    expect(shown.map((s) => s.id), entranceIds);
  });
}
