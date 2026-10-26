import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/domain/search_copy.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_fare.dart';

RideSnapshot snap({double price = 259}) => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: price,
  paymentMethod: 'Apple Pay',
  rideId: 'r1',
);

FindingDriverController controllerOf(
  MockRideRealtime rt,
  RideSession ride, {
  Duration delayedAfter = SearchCopy.delayedAfter,
  Duration? priceBumpAfter,
  Duration searchTimeout = const Duration(minutes: 3),
  ApiClient? api,
}) {
  return FindingDriverController(
    realtime: rt,
    ride: ride,
    store: FindingDriverRepository(),
    delayedAfter: delayedAfter,
    priceBumpAfter: priceBumpAfter,
    searchTimeout: searchTimeout,
    api: api,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('duplicate assignment matches once', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    var matches = 0;
    final controller = controllerOf(rt, ride);
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    rt.emit(RideStatus.driverAssigned, sequence: 2);
    rt.emit(RideStatus.driverAssigned, sequence: 3);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(matches, 1);
    controller.dispose();
    rt.dispose();
  });

  test('assignment after cancel does not match', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    var matches = 0;
    final controller = controllerOf(rt, ride);
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    // Server-first: the assignment lands while the cancel is in flight.
    final cancelling = controller.cancelSearch();
    rt.emit(RideStatus.driverAssigned, sequence: 9);
    await cancelling;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(matches, 0);
    expect(ride.suppressRestore, isTrue);
    expect(await RideSnapshotStore.read(), isNull);
    controller.dispose();
    rt.dispose();
  });

  test('save after cancel cannot revive the snapshot', () async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    final pending = RideSnapshotStore.save(
      snap().copyWith(status: RideStatus.driverAssigned),
    );
    await RideSnapshotStore.clear();
    await pending;
    expect(await RideSnapshotStore.read(), isNull);
  });

  test('event after dispose has no effect', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    var matches = 0;
    final controller = controllerOf(rt, ride);
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    controller.dispose();
    rt.emit(RideStatus.driverAssigned, sequence: 4);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(matches, 0);
    rt.dispose();
  });

  test('stale sequence is ignored', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    var matches = 0;
    final controller = controllerOf(rt, ride);
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    rt.emit(RideStatus.findingDriver, sequence: 5);
    rt.emit(RideStatus.driverAssigned, sequence: 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(matches, 0);
    controller.dispose();
    rt.dispose();
  });

  test('search timeout keeps searching until the server says no driver, '
      'then terminates once', () async {
    final server = InProcessMockClient();
    server.rides['r1'] = {'id': 'r1', 'status': 'findingDriver', 'version': 1};
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    final terminal = <RideStatus>[];
    final controller = controllerOf(
      rt,
      ride,
      searchTimeout: const Duration(seconds: 2),
      api: ApiClient(client: server),
    );
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () {},
      onTerminal: terminal.add,
    );
    // ARCH-3: the client mark is a UI hint, not the end of the ride.
    controller.debugAdvance(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.stillLooking, isTrue);
    expect(ride.status, isNot(RideStatus.noDriverFound));
    expect(terminal, isEmpty);

    // The server ends the search; the next check reports it.
    server.rides['r1']!
      ..['status'] = 'noDriverFound'
      ..['version'] = 2;
    await controller.checkServerSearchState();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ride.status, RideStatus.noDriverFound);
    expect(terminal, <RideStatus>[RideStatus.noDriverFound]);
    controller.debugAdvance(30);
    await controller.checkServerSearchState();
    await Future<void>.delayed(Duration.zero);
    expect(terminal, hasLength(1));
    controller.dispose();
    rt.dispose();
  });

  test('delayed search does not assign a driver by itself', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    var matches = 0;
    final controller = controllerOf(
      rt,
      ride,
      delayedAfter: Duration.zero,
      priceBumpAfter: Duration.zero,
    );
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(matches, 0);
    expect(controller.isDelayed, isTrue);
    expect(controller.showPriceBump, isTrue);
    expect(controller.timeoutLogs, 1);
    controller.dispose();
    rt.dispose();
  });

  test(
    'assignment after cancel does not match when event arrives later',
    () async {
      final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
      final ride = RideSession()..rideId = 'r1';
      var matches = 0;
      final controller = controllerOf(rt, ride);
      controller.start(
        snapshot: snap(),
        onTick: (_) {},
        onMatched: () => matches += 1,
      );
      await controller.cancelSearch();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      rt.emit(RideStatus.driverAssigned, sequence: 20);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(matches, 0);
      controller.dispose();
      rt.dispose();
    },
  );

  test('resume resync then older realtime assignment is ignored', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    var matches = 0;
    final controller = controllerOf(rt, ride);
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    rt.emit(RideStatus.findingDriver, sequence: 8);
    await controller.resync();
    rt.emit(RideStatus.driverAssigned, sequence: 1);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(matches, 0);
    controller.dispose();
    rt.dispose();
  });

  test('price bump updates the same ride and dismisses the card', () async {
    SharedPreferences.setMockInitialValues({});
    final httpClient = InProcessMockClient();
    httpClient.rides['r1'] = {
      'id': 'r1',
      'status': 'findingDriver',
      'price': 259,
      'pickupLat': 59.3,
      'pickupLng': 18.0,
    };
    final api = ApiClient(client: httpClient);
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1), api: api);
    final ride = RideSession()..rideId = 'r1';
    final controller = controllerOf(
      rt,
      ride,
      delayedAfter: Duration.zero,
      priceBumpAfter: Duration.zero,
      api: api,
    );
    controller.start(snapshot: snap(), onTick: (_) {}, onMatched: () {});
    expect(controller.showPriceBump, isTrue);
    final ok = await controller.confirmPriceIncrease(20);
    expect(ok, isTrue);
    expect(controller.currentPrice, 279);
    expect(controller.showPriceBump, isFalse);
    expect(controller.offerConfirmation, 'Updated offer: 279 kr');
    expect(mockFareKr(httpClient.rides['r1']), 279);
    expect(ride.rideId, 'r1');
    controller.dismissPriceBump();
    expect(controller.showPriceBump, isFalse);
    controller.dispose();
    rt.dispose();
  });

  test('custom typed offer updates the same rideId', () async {
    SharedPreferences.setMockInitialValues({});
    final httpClient = InProcessMockClient();
    httpClient.rides['r1'] = {
      'id': 'r1',
      'status': 'findingDriver',
      'price': 259,
      'pickupLat': 59.3,
      'pickupLng': 18.0,
    };
    final api = ApiClient(client: httpClient);
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1), api: api);
    final ride = RideSession()..rideId = 'r1';
    final controller = controllerOf(
      rt,
      ride,
      delayedAfter: Duration.zero,
      api: api,
    );
    controller.start(snapshot: snap(), onTick: (_) {}, onMatched: () {});
    final ok = await controller.confirmPriceIncrease(81);
    expect(ok, isTrue);
    expect(controller.currentPrice, 340);
    expect(ride.rideId, 'r1');
    expect(mockFareKr(httpClient.rides['r1']), 340);
    controller.dismissPriceBump();
    expect(controller.showPriceBump, isFalse);
    controller.dispose();
    rt.dispose();
  });

  test('closing the bump keeps searching at the original price', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    final controller = controllerOf(rt, ride, delayedAfter: Duration.zero);
    controller.start(snapshot: snap(), onTick: (_) {}, onMatched: () {});
    controller.dismissPriceBump();
    expect(controller.currentPrice, 259);
    expect(controller.showPriceBump, isFalse);
    expect(controller.matchCount, 0);
    controller.dispose();
    rt.dispose();
  });

  test('debug advance reaches delayed copy without matching', () {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    final controller = controllerOf(rt, ride);
    controller.start(snapshot: snap(), onTick: (_) {}, onMatched: () {});
    controller.debugAdvance(60);
    expect(controller.isDelayed, isTrue);
    expect(controller.copy.headline, "It's busier than usual");
    expect(controller.matchCount, 0);
    controller.dispose();
    rt.dispose();
  });

  test(
    'local cancel succeeds when adapter 404s and ignores later assignment',
    () async {
      SharedPreferences.setMockInitialValues({});
      final httpClient = InProcessMockClient();
      final api = ApiClient(client: httpClient);
      final rt = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        api: api,
      );
      final ride = RideSession()..rideId = 'r1';
      var matches = 0;
      final store = FindingDriverRepository();
      await store.save(snap());
      expect(await RideSnapshotStore.read(), isNotNull);
      final controller = FindingDriverController(
        realtime: rt,
        ride: ride,
        store: store,
        api: api,
      );
      controller.start(
        snapshot: snap(),
        onTick: (_) {},
        onMatched: () => matches += 1,
      );
      // Server-first: the 404 answer commits the cancel.
      await controller.cancelSearch(reasonId: 'wait_too_long');
      expect(ride.status, RideStatus.cancelledByRider);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(await RideSnapshotStore.read(), isNull);
      rt.emit(RideStatus.driverAssigned, sequence: 9);
      rt.assignNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(matches, 0);
      expect(controller.matchCount, 0);
      controller.dispose();
      rt.dispose();
    },
  );

  test('mock assignment matches and carries the driver through', () async {
    final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
    final ride = RideSession()..rideId = 'r1';
    var matches = 0;
    final controller = controllerOf(rt, ride);
    controller.start(
      snapshot: snap(),
      onTick: (_) {},
      onMatched: () => matches += 1,
    );
    rt.assignNow();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(matches, 1);
    expect(controller.matchCount, 1);
    expect(ride.status, RideStatus.driverAssigned);
    expect(controller.matchedDriver, isNotNull);
    final stored = await RideSnapshotStore.read();
    expect(stored?.status, RideStatus.driverAssigned);
    expect(stored?.driver, isNotNull);
    controller.dispose();
    rt.dispose();
  });
}
