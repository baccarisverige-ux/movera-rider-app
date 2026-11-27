// 2026-11-27 (owner: "Le chauffeur a fini la course mais rider reste
// bloquee"): a trip accepted and finished while the app was in the
// background is first seen completed. Finding leaves for Ride completed
// (never a cancel, never archived cancelled, never searching again).
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backend extends http.BaseClient {
  _Backend(this.inner);
  final InProcessMockClient inner;
  int cancelPosts = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'POST' && request.url.path.endsWith('/cancel')) {
      cancelPosts += 1;
    }
    return inner.send(request);
  }
}

RideSnapshot _snapshot(String rideId) => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: DateTime.now(),
  searchStartedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Cash',
  rideId: rideId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  Future<
    ({
      FindingDriverController controller,
      MockRideRealtime realtime,
      _Backend backend,
      InProcessMockClient server,
      List<RideStatus> completed,
      List<RideStatus> terminal,
      List<bool> matched,
    })
  >
  begin() async {
    final server = InProcessMockClient();
    final backend = _Backend(server);
    server.rides['r1'] = {'id': 'r1', 'status': 'findingDriver', 'version': 1};
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    addTearDown(realtime.dispose);
    final ride = RideSession()..rideId = 'r1';
    final controller = FindingDriverController(
      realtime: realtime,
      ride: ride,
      store: FindingDriverRepository(),
      api: ApiClient(client: backend),
      searchTimeout: const Duration(days: 1),
    );
    addTearDown(controller.dispose);
    final snapshot = _snapshot('r1');
    await RideSnapshotStore.save(snapshot);
    final completed = <RideStatus>[];
    final terminal = <RideStatus>[];
    final matched = <bool>[];
    controller.start(
      snapshot: snapshot,
      onTick: (_) {},
      onMatched: () => matched.add(true),
      onTerminal: terminal.add,
      onCompleted: completed.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (
      controller: controller,
      realtime: realtime,
      backend: backend,
      server: server,
      completed: completed,
      terminal: terminal,
      matched: matched,
    );
  }

  test(
    'stream: searching -> completed leaves Finding for Ride completed',
    () async {
      final t = await begin();
      t.realtime.emit(RideStatus.tripCompleted);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(t.completed, [RideStatus.tripCompleted]);
      expect(t.terminal, isEmpty);
      expect(t.controller.cancelled, isFalse);
      final stored = await RideSnapshotStore.read();
      expect(stored?.rideId, 'r1');
      expect(stored?.status, RideStatus.tripCompleted);
    },
  );

  test(
    'stream: every completed status leaves Finding (rating pending)',
    () async {
      final t = await begin();
      t.realtime.emit(RideStatus.ratingPending);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(t.completed, [RideStatus.ratingPending]);
      expect(t.terminal, isEmpty);
    },
  );

  test('server check: searching -> completed leaves Finding', () async {
    final t = await begin();
    t.server.rides['r1'] = {'id': 'r1', 'status': 'completed', 'version': 9};
    await t.controller.checkServerSearchState();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(t.completed, hasLength(1));
    expect(t.completed.single.isCompletedSurface, isTrue);
    expect(t.terminal, isEmpty);
    expect(t.controller.cancelled, isFalse);
    expect((await RideSnapshotStore.read())?.status.isCompletedSurface, isTrue);
  });

  test('cancel refused on a completed trip lands on Ride completed, '
      'no new search', () async {
    final t = await begin();
    t.server.rides['r1'] = {'id': 'r1', 'status': 'completed', 'version': 9};
    final result = await t.controller.cancelSearch(reasonId: 'changed_mind');
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(t.backend.cancelPosts, greaterThanOrEqualTo(1));
    expect(result, isNot(SearchCancelResult.confirmed));
    expect(t.completed, hasLength(1));
    expect(t.completed.single.isCompletedSurface, isTrue);
    expect(t.terminal, isEmpty);
    expect(t.controller.cancelled, isFalse);
    expect(t.matched, isEmpty);
  });
}
