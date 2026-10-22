import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wave 5 R5.4 parts c + d: state and time (low). One test per bug.
const _env = AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://x.invalid');

/// An API whose every request is answered by [answer].
ApiClient _api(Future<http.Response> Function(http.Request request) answer) =>
    ApiClient(env: _env, client: MockClient(answer));

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

/// A ride searching since [startedAt].
RideSnapshot _searching(String rideId, DateTime startedAt) => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: startedAt,
  searchStartedAt: startedAt,
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.33,
  pickupLng: 18.06,
  destinationLat: 59.34,
  destinationLng: 18.07,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: rideId,
);

/// What [_finding] started; [_closeAll] stops it.
final _open = <void Function()>[];

void _closeAll() {
  FindingDriverController.active = null;
  for (final close in _open) {
    close();
  }
  _open.clear();
}

/// Starts a Finding controller for [rideId] searching since [startedAt],
/// reading the time from [now]. Widget tests call [_closeAll] at the end.
FindingDriverController _finding(
  ApiClient api,
  String rideId,
  DateTime startedAt, {
  DateTime Function()? now,
  void Function(RideStatus status)? onTerminal,
}) {
  final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
  final controller = FindingDriverController(
    realtime: realtime,
    ride: RideSession()..rideId = rideId,
    store: FindingDriverRepository(),
    api: api,
    now: now,
  );
  controller.start(
    snapshot: _searching(rideId, startedAt),
    onTick: (_) {},
    onMatched: () {},
    onTerminal: onTerminal ?? (_) {},
  );
  _open.addAll([controller.dispose, realtime.dispose]);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
  });
  tearDown(_closeAll);

  testWidgets('rider-u94: after the app was paused the search time catches '
      'up on the next tick', (tester) async {
    var clock = DateTime(2026, 5, 4, 12);
    final controller = _finding(
      _api((_) async => _json({'code': 'OK', 'vehicles': []})),
      'ride_u94',
      clock.subtract(const Duration(seconds: 30)),
      now: () => clock,
    );
    // Four minutes in the background: no timer ran.
    clock = clock.add(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.elapsedSeconds, greaterThanOrEqualTo(270));
    expect(controller.stillLooking, isTrue);
    _closeAll();
  });

  test('rider-u100: a refused cancel resumes the search at its real elapsed '
      'time', () async {
    var clock = DateTime(2026, 5, 4, 12);
    final answer = Completer<http.Response>();
    final controller = _finding(
      _api((request) {
        if (request.url.path.endsWith('/cancel')) return answer.future;
        return Future.value(_json({'code': 'OK', 'vehicles': []}));
      }),
      'ride_u100',
      clock,
      now: () => clock,
    );
    final cancel = controller.cancelSearch();
    // Two minutes waiting on the cancel, then the server refuses it.
    clock = clock.add(const Duration(minutes: 2));
    answer.complete(_json({'code': 'invalid_transition'}, 422));
    expect(await cancel, SearchCancelResult.rejected);
    expect(controller.elapsedSeconds, greaterThanOrEqualTo(120));
  });
}
