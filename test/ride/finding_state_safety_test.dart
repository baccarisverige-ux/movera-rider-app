import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mock_fare.dart';

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

FindingDriverController _controller({
  required MockRideRealtime realtime,
  required RideSession ride,
  required ApiClient api,
}) {
  return FindingDriverController(
    realtime: realtime,
    ride: ride,
    api: api,
    store: FindingDriverRepository(),
    delayedAfter: Duration.zero,
  );
}

Map<String, dynamic> _rideJson({String status = 'findingDriver'}) => {
  'id': 'r1',
  'status': status,
  'price': 259,
  'pickupAddress': 'Pickup A',
  'pickupLat': 59.30,
  'pickupLng': 18.00,
  'destinationAddress': 'Destination',
  'destinationLat': 59.40,
  'destinationLng': 18.10,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
  });

  test('price commit before assignment stays applied without rollback', () async {
    final transport = InProcessMockClient(
      latency: const Duration(milliseconds: 60),
    )..rides['r1'] = _rideJson();
    final api = ApiClient(client: transport);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(milliseconds: 10),
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

    final changed = await controller.confirmPriceIncrease(20);
    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(changed, isTrue);
    expect(controller.currentPrice, 279);
    expect(mockFareKr(transport.rides['r1']), 279);
    expect(transport.rides['r1']?['status'], 'accepted');
    expect(ride.status, RideStatus.driverAssigned);
    expect(matches, 1);
    final stored = await RideSnapshotStore.read();
    expect(stored?.price, 279);
    expect(stored?.status, RideStatus.driverAssigned);

    controller.dispose();
    realtime.dispose();
  });

  test('mock PATCH rejects edits after a ride is already assigned', () async {
    final transport = InProcessMockClient()
      ..rides['r1'] = _rideJson(status: 'driverAssigned');
    final api = ApiClient(client: transport);

    await expectLater(
      api.patch('/api/v1/rides/r1', body: {'price': 309}),
      throwsA(isA<ApiError>()),
    );

    // Refused: the seeded record is left exactly as it was.
    expect(transport.rides['r1']?['status'], 'driverAssigned');
    expect(mockFareKr(transport.rides['r1']), 259);
  });

  test('pickup edit updates snapshot, mock ride and nearby search together', () async {
    final transport = InProcessMockClient()..rides['r1'] = _rideJson();
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

    final changed = await controller.updatePickup(
      address: 'Pickup B',
      latitude: 59.35,
      longitude: 18.07,
    );

    expect(changed, isTrue);
    expect(controller.pickupAddress, 'Pickup B');
    expect(controller.pickupLat, 59.35);
    expect(controller.pickupLng, 18.07);
    expect(transport.rides['r1']?['pickupAddress'], 'Pickup B');
    expect(transport.rides['r1']?['pickupLat'], 59.35);
    expect(transport.rides['r1']?['pickupLng'], 18.07);
    expect(controller.nearby, hasLength(3));
    expect(controller.nearby.first.latitude, closeTo(59.3521, 0.000001));
    expect(controller.nearby.first.longitude, closeTo(18.0686, 0.000001));

    final stored = await RideSnapshotStore.read();
    expect(stored?.pickupAddress, 'Pickup B');
    expect(stored?.pickupLat, 59.35);
    expect(stored?.pickupLng, 18.07);

    controller.dispose();
    realtime.dispose();
  });

  test('late nearby response after cancel cannot mutate the search', () async {
    final transport = InProcessMockClient(
      latency: const Duration(milliseconds: 60),
    )..rides['r1'] = _rideJson();
    final api = ApiClient(client: transport);
    final realtime = MockRideRealtime(
      assignAfter: const Duration(days: 1),
      api: api,
    );
    final ride = RideSession()..rideId = 'r1';
    final controller = _controller(realtime: realtime, ride: ride, api: api);
    var ticks = 0;

    controller.start(
      snapshot: _snapshot(),
      onTick: (_) => ticks += 1,
      onMatched: () {},
    );
    final ticksBeforeCancel = ticks;

    await controller.cancelSearch();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(ride.status, RideStatus.cancelledByRider);
    expect(controller.nearby, isEmpty);
    expect(ticks, ticksBeforeCancel);
    expect(await RideSnapshotStore.read(), isNull);

    controller.dispose();
    realtime.dispose();
  });
}
