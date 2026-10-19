import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot _snapshot({
  String pickupAddress = 'Pickup A',
  double pickupLat = 59.30,
  double pickupLng = 18.00,
  double price = 259,
}) {
  return RideSnapshot(
    status: RideStatus.findingDriver,
    savedAt: DateTime.now(),
    pickupAddress: pickupAddress,
    destinationAddress: 'Destination',
    pickupLat: pickupLat,
    pickupLng: pickupLng,
    destinationLat: 59.40,
    destinationLng: 18.10,
    rideType: 'Movera',
    price: price,
    paymentMethod: 'Apple Pay',
    rideId: 'r1',
  );
}

Map<String, dynamic> _rideJson() => {
  'id': 'r1',
  'status': 'findingDriver',
  'price': 259,
  'pickupAddress': 'Pickup A',
  'pickupLat': 59.30,
  'pickupLng': 18.00,
  'destinationAddress': 'Destination',
  'destinationLat': 59.40,
  'destinationLng': 18.10,
};

FindingDriverController _controller({
  required MockRideRealtime realtime,
  required RideSession ride,
  required ApiClient api,
  FindingDriverRepository? store,
}) {
  return FindingDriverController(
    realtime: realtime,
    ride: ride,
    api: api,
    store: store ?? FindingDriverRepository(),
    delayedAfter: const Duration(days: 1),
  );
}

class _BlockingRepository extends FindingDriverRepository {
  bool _blockNext = false;
  Completer<void>? _entered;
  Completer<void>? _release;

  Future<void> blockNextSave() {
    _blockNext = true;
    _entered = Completer<void>();
    _release = Completer<void>();
    return _entered!.future;
  }

  void release() {
    final release = _release;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<void> save(RideSnapshot snapshot) async {
    if (_blockNext) {
      _blockNext = false;
      final entered = _entered;
      if (entered != null && !entered.isCompleted) entered.complete();
      await _release!.future;
    }
    await super.save(snapshot);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
  });

  test('price edit that commits first is preserved through assignment', () async {
    final transport = InProcessMockClient(
      latency: const Duration(milliseconds: 50),
    )..rides['r1'] = _rideJson();
    final api = ApiClient(client: transport);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    final ride = RideSession()..rideId = 'r1';
    final controller = _controller(realtime: realtime, ride: ride, api: api);
    var matches = 0;

    controller.start(
      snapshot: _snapshot(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );

    final edit = controller.confirmPriceIncrease(20);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    realtime.assignNow();

    final changed = await edit;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(changed, isTrue);
    expect(controller.currentPrice, 279);
    expect(transport.rides['r1']?['price'], 279);
    expect(transport.rides['r1']?['status'], 'accepted');
    expect(ride.status, RideStatus.driverAssigned);
    expect(matches, 1);
    final stored = await RideSnapshotStore.read();
    expect(stored?.price, 279);
    expect(stored?.status, RideStatus.driverAssigned);

    controller.dispose();
    realtime.dispose();
  });

  test('assignment that commits first rejects a later price edit', () async {
    final transport = InProcessMockClient(
      latency: const Duration(milliseconds: 50),
    )..rides['r1'] = _rideJson();
    final api = ApiClient(client: transport);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    final ride = RideSession()..rideId = 'r1';
    final controller = _controller(realtime: realtime, ride: ride, api: api);

    controller.start(
      snapshot: _snapshot(),
      onTick: (_) {},
      onMatched: () {},
    );

    realtime.assignNow();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final changed = await controller.confirmPriceIncrease(20);
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(changed, isFalse);
    expect(controller.currentPrice, 259);
    expect(transport.rides['r1']?['price'], 259);
    expect(transport.rides['r1']?['status'], 'accepted');
    expect(ride.status, RideStatus.driverAssigned);

    controller.dispose();
    realtime.dispose();
  });

  test('pickup edit that commits first is preserved through assignment', () async {
    final transport = InProcessMockClient(
      latency: const Duration(milliseconds: 50),
    )..rides['r1'] = _rideJson();
    final api = ApiClient(client: transport);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    final ride = RideSession()..rideId = 'r1';
    final controller = _controller(realtime: realtime, ride: ride, api: api);

    controller.start(
      snapshot: _snapshot(),
      onTick: (_) {},
      onMatched: () {},
    );

    final edit = controller.updatePickup(
      address: 'Pickup B',
      latitude: 59.35,
      longitude: 18.07,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    realtime.assignNow();

    final changed = await edit;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(changed, isTrue);
    expect(controller.pickupAddress, 'Pickup B');
    expect(controller.pickupLat, 59.35);
    expect(controller.pickupLng, 18.07);
    expect(transport.rides['r1']?['pickupAddress'], 'Pickup B');
    expect(transport.rides['r1']?['pickupLat'], 59.35);
    expect(transport.rides['r1']?['pickupLng'], 18.07);
    expect(transport.rides['r1']?['status'], 'accepted');
    expect(ride.status, RideStatus.driverAssigned);
    final stored = await RideSnapshotStore.read();
    expect(stored?.pickupAddress, 'Pickup B');
    expect(stored?.status, RideStatus.driverAssigned);

    controller.dispose();
    realtime.dispose();
  });

  test('assignment waits for an edit snapshot save to finish', () async {
    final transport = InProcessMockClient()..rides['r1'] = _rideJson();
    final api = ApiClient(client: transport);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    final ride = RideSession()..rideId = 'r1';
    final store = _BlockingRepository();
    final controller = _controller(
      realtime: realtime,
      ride: ride,
      api: api,
      store: store,
    );
    var matches = 0;

    controller.start(
      snapshot: _snapshot(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );

    final entered = store.blockNextSave();
    final edit = controller.updatePickup(
      address: 'Pickup B',
      latitude: 59.35,
      longitude: 18.07,
    );
    await entered;

    realtime.emit(RideStatus.driverAssigned, sequence: 10);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(matches, 0);

    store.release();
    final changed = await edit;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(changed, isTrue);
    expect(ride.status, RideStatus.driverAssigned);
    expect(matches, 1);
    expect(controller.pickupAddress, 'Pickup B');
    final stored = await RideSnapshotStore.read();
    expect(stored?.pickupAddress, 'Pickup B');
    expect(stored?.status, RideStatus.driverAssigned);

    controller.dispose();
    realtime.dispose();
  });
}
