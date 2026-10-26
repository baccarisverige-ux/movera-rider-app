import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every request fails, as if the device were offline.
class _OfflineHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw const SocketExceptionStub();
  }
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketExceptionStub: no network';
}

RideSnapshot snap() => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: 'r1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  test(
    'a cancel the backend never acknowledges is persisted for later retry',
    () async {
      final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
      final ride = RideSession()..rideId = 'r1';
      final api = ApiClient(client: _OfflineHttpClient());
      final controller = FindingDriverController(
        realtime: rt,
        ride: ride,
        store: FindingDriverRepository(),
        api: api,
      );
      controller.start(snapshot: snap(), onTick: (_) {}, onMatched: () {});

      await controller.cancelSearch();
      // cancelSearch fires the backend call in the background; give both
      // retry attempts a chance to run and fail.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final pending = await PendingCancelStore.all();
      expect(pending, hasLength(1));
      expect(pending.single.rideId, 'r1');

      controller.dispose();
      rt.dispose();
    },
  );

  test(
    'a cancel the backend acknowledges is never persisted as pending',
    () async {
      final rt = MockRideRealtime(assignAfter: const Duration(days: 1));
      final ride = RideSession()..rideId = 'r1';
      final backend = InProcessMockClient();
      backend.rides['r1'] = {'id': 'r1', 'status': 'findingDriver'};
      final api = ApiClient(client: backend);
      final controller = FindingDriverController(
        realtime: rt,
        ride: ride,
        store: FindingDriverRepository(),
        api: api,
      );
      controller.start(snapshot: snap(), onTick: (_) {}, onMatched: () {});

      await controller.cancelSearch();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await PendingCancelStore.all(), isEmpty);

      controller.dispose();
      rt.dispose();
    },
  );

  test(
    'flushPendingCancels retries a stranded cancel and clears it on success',
    () async {
      await PendingCancelStore.add(
        const PendingCancel(rideId: 'r2', reasonId: 'plans_changed'),
      );

      final backend = InProcessMockClient();
      backend.rides['r2'] = {'id': 'r2', 'status': 'findingDriver'};
      final api = ApiClient(client: backend);

      await FindingDriverController.flushPendingCancels(api: api);

      expect(await PendingCancelStore.all(), isEmpty);
    },
  );

  test('flushPendingCancels leaves a still-failing cancel pending', () async {
    await PendingCancelStore.add(const PendingCancel(rideId: 'r3'));
    final api = ApiClient(client: _OfflineHttpClient());

    await FindingDriverController.flushPendingCancels(api: api);

    final pending = await PendingCancelStore.all();
    expect(pending, hasLength(1));
    expect(pending.single.rideId, 'r3');
  });
}
