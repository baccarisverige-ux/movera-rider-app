import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/booking/application/booking_coordinator.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A transport whose events the test writes by hand, server times included.
class _ScriptedRealtime extends RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast();

  void add(RideRealtimeEvent event) => _events.add(event);

  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _events.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void dispose() => _events.close();
}

RideSnapshot _searching({
  required DateTime savedAt,
  int? version,
  DateTime? serverUpdatedAt,
  String rideId = 'ride_1',
}) => RideSnapshot(
  status: RideStatus.searchDelayed,
  savedAt: savedAt,
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: rideId,
  version: version,
  serverUpdatedAt: serverUpdatedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..status = RideStatus.idle;
  });

  test('ARCH-1: a versioned assignment is accepted over an unversioned '
      'session whatever its timestamp', () {
    final t0 = DateTime.utc(2026, 10, 14, 12);
    final session = RideSession();
    session.backendReconcile(
      RideStatus.searchDelayed,
      id: 'ride_1',
      updatedAt: t0.add(const Duration(seconds: 30)),
    );
    final accepted = session.backendReconcile(
      RideStatus.driverAssigned,
      id: 'ride_1',
      version: 2,
      updatedAt: t0.add(const Duration(seconds: 29)),
    );
    expect(accepted, isTrue);
    expect(session.status, RideStatus.driverAssigned);
    expect(session.authoritativeVersion, 2);
  });

  test('ARCH-1: restore seeds server ordering, never the device savedAt', () {
    final t0 = DateTime.utc(2026, 10, 14, 12);
    // Device clock ahead of the server: the local save is "later" than the
    // server's assignment.
    final snapshot = _searching(
      savedAt: DateTime.now(),
      version: 1,
      serverUpdatedAt: t0,
    );
    RideRestoreCoordinator(reader: () async => snapshot).pageFor(snapshot);
    final session = AppScope.instance.ride;
    expect(session.authoritativeVersion, 1);
    expect(session.authoritativeUpdatedAt, t0);

    final accepted = session.backendReconcile(
      RideStatus.driverAssigned,
      id: 'ride_1',
      version: 2,
      updatedAt: t0.add(const Duration(seconds: 29)),
    );
    expect(accepted, isTrue);
  });

  test('ARCH-1: an old snapshot without server ordering does not block the '
      'first assignment after restore', () {
    final snapshot = _searching(savedAt: DateTime.now());
    RideRestoreCoordinator(reader: () async => snapshot).pageFor(snapshot);
    final session = AppScope.instance.ride;
    expect(session.authoritativeUpdatedAt, isNull);
    final accepted = session.backendReconcile(
      RideStatus.driverAssigned,
      id: 'ride_1',
      version: 2,
      updatedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );
    expect(accepted, isTrue);
  });

  test('ARCH-1: restored search moves on to the driver whose server time is '
      'earlier than the local save', () async {
    final t0 = DateTime.now().toUtc().subtract(const Duration(seconds: 40));
    final session = RideSession()
      // What a restore used to seed: device time, no server version.
      ..backendReconcile(
        RideStatus.searchDelayed,
        id: 'ride_1',
        updatedAt: t0.add(const Duration(seconds: 30)),
      );
    final realtime = _ScriptedRealtime();
    addTearDown(realtime.dispose);
    final controller = FindingDriverController(
      realtime: realtime,
      ride: session,
      store: FindingDriverRepository(),
    );
    addTearDown(controller.dispose);
    var matched = 0;
    controller.start(
      snapshot: _searching(savedAt: t0.add(const Duration(seconds: 30))),
      onTick: (_) {},
      onMatched: () => matched += 1,
    );
    realtime.add(
      RideRealtimeEvent(
        tripId: 'ride_1',
        status: RideStatus.driverAssigned,
        sequence: 2,
        version: 2,
        serverTime: t0.add(const Duration(seconds: 29)),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(session.status, RideStatus.driverAssigned);
    expect(matched, 1);
  });

  test('RIDE-17 / ARCH-1: the first snapshot carries stops, the server '
      'version and updatedAt, and the booked ids', () async {
    final api = ApiClient(client: InProcessMockClient());
    final booking = BookingCoordinator(api: api);
    final id = await booking.submitFinding(
      pickupAddress: 'Stockholm Central',
      destinationAddress: 'Arlanda',
      pickupLat: 59.33,
      pickupLng: 18.06,
      destinationLat: 59.65,
      destinationLng: 17.92,
      rideType: 'economy',
      price: 259,
      paymentMethod: 'visa',
      rideTypeLabel: 'Movera',
      paymentMethodLabel: 'Visa •••• 4242',
      stops: const [
        RouteStop(address: 'Solna', latitude: 59.36, longitude: 18.0),
      ],
    );
    final stored = await RideSnapshotStore.read();
    expect(stored?.rideId, id);
    expect(stored!.stops, hasLength(1));
    expect(stored.stops.single.address, 'Solna');
    expect(stored.version, 1);
    expect(stored.serverUpdatedAt, isNotNull);
    expect(stored.categoryId, 'economy');
    expect(stored.paymentMethodId, 'visa');
    expect(stored.rideType, 'Movera');
    expect(AppScope.instance.ride.bookedCategoryId, 'economy');
  });

  test('PR-3 gap: a reload with this ride\'s cancel still queued restores '
      'Home, archives the cancel and drops the snapshot', () async {
    final snapshot = _searching(savedAt: DateTime.now(), rideId: 'ride_q');
    await RideSnapshotStore.save(snapshot);
    await PendingCancelStore.enqueue(rideId: 'ride_q');
    final coordinator = RideRestoreCoordinator(
      reader: RideSnapshotStore.read,
      resync: (_) async {},
      authRequired: () => false,
    );
    final page = await coordinator.root();
    expect(page, isA<Home>());
    expect(coordinator.showing, RestoredSurface.home);
    expect(await RideSnapshotStore.read(), isNull);
    final history = await OnDemandRideHistoryStore.read();
    expect(history.single.reservationId, 'ondemand-ride_q');
    expect(history.single.status.name, 'cancelled');
  });

  test('a reload with no queued cancel still restores the search', () async {
    final snapshot = _searching(savedAt: DateTime.now(), rideId: 'ride_live');
    await RideSnapshotStore.save(snapshot);
    final coordinator = RideRestoreCoordinator(
      reader: RideSnapshotStore.read,
      resync: (_) async {},
      authRequired: () => false,
    );
    await coordinator.root();
    expect(coordinator.showing, RestoredSurface.finding);
    expect(await RideSnapshotStore.read(), isNotNull);
  });

  test(
    'NAV-15: firstRootResolved waits for the first root() to resolve',
    () async {
      final read = Completer<RideSnapshot?>();
      final coordinator = RideRestoreCoordinator(
        reader: () => read.future,
        resync: (_) async {},
        authRequired: () => false,
      );
      var resolved = false;
      final rooting = coordinator.root();
      unawaited(coordinator.firstRootResolved.then((_) => resolved = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resolved, isFalse);
      read.complete(null);
      await rooting;
      await coordinator.firstRootResolved;
      expect(resolved, isTrue);
    },
  );
}
