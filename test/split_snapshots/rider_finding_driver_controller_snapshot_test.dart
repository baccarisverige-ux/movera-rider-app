import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Base split (2026-11-05): the Finding driver controller split with no
// behaviour change. This trace (the controller's QA snapshot and every
// request it sends, step by step) was written before the split and must
// match after it.

class _Backend extends http.BaseClient {
  _Backend(this.inner);
  final InProcessMockClient inner;
  final List<String> log = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    log.add('${request.method} ${request.url.path}');
    return inner.send(request);
  }
}

final _start = DateTime.utc(2030, 1, 1, 12);

RideSnapshot _snapshot(String rideId) => RideSnapshot(
  status: RideStatus.findingDriver,
  savedAt: _start,
  searchStartedAt: _start,
  pickupAddress: 'Klockarvägen 37',
  destinationAddress: 'Arlanda Airport',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.4,
  destinationLng: 18.1,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'Apple Pay',
  rideId: rideId,
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 40));

void _expectTrace(String name, String now) {
  final file = File('test/split_snapshots/$name.txt');
  if (autoUpdateGoldenFiles) {
    file.writeAsStringSync(now);
    return;
  }
  expect(file.existsSync(), isTrue, reason: 'Run --update-goldens once');
  expect(now, file.readAsStringSync(), reason: 'The $name trace changed');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
  });

  Future<String> run(
    String rideId,
    Future<void> Function(FindingDriverController c, StringBuffer out) steps,
  ) async {
    final server = InProcessMockClient();
    server.rides[rideId] = {
      'id': rideId,
      'status': 'findingDriver',
      'version': 1,
    };
    final backend = _Backend(server);
    final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
    addTearDown(realtime.dispose);
    final ride = RideSession()..rideId = rideId;
    var clock = _start;
    final out = StringBuffer();
    final controller = FindingDriverController(
      realtime: realtime,
      ride: ride,
      store: FindingDriverRepository(),
      api: ApiClient(client: backend),
      searchTimeout: const Duration(seconds: 30),
      priceBumpAfter: const Duration(seconds: 10),
      now: () => clock,
    );
    addTearDown(controller.dispose);
    final snapshot = _snapshot(rideId);
    await RideSnapshotStore.save(snapshot);
    controller.start(
      snapshot: snapshot,
      onTick: (e) => out.writeln('tick $e'),
      onMatched: () => out.writeln('matched'),
      onTerminal: (s) => out.writeln('terminal ${s.name}'),
    );
    void mark(String step) {
      out
        ..writeln('# $step')
        ..writeln(jsonEncode(controller.qaSnapshot()))
        ..writeln('requests ${backend.log}');
      backend.log.clear();
    }

    mark('start');
    await steps(controller, out);
    clock = clock.add(Duration(seconds: controller.elapsedSeconds));
    mark('end');
    return out.toString();
  }

  test('finding driver controller: wait, bump, raise, timeout, cancel', () async {
    final trace = await run('split-fd-1', (c, out) async {
      c.debugAdvance(12);
      await _settle();
      out.writeln(jsonEncode(c.qaSnapshot()));
      out.writeln(
        'raise ${await c.confirmPriceIncreaseBy(Money.fromLegacyMajor(20, c.currency))}',
      );
      await _settle();
      out.writeln(jsonEncode(c.qaSnapshot()));
      c.debugAdvance(30);
      await _settle();
      out.writeln(jsonEncode(c.qaSnapshot()));
      c.keepSearching();
      out.writeln('cancel ${await c.cancelSearch()}');
      await _settle();
      out.writeln(jsonEncode(c.qaSnapshot()));
    });
    _expectTrace('rider_finding_driver_controller', trace);
  });

  test('finding driver controller: server says no driver found', () async {
    final trace = await run('split-fd-2', (c, out) async {
      c.debugAdvance(31);
      await _settle();
      out.writeln(jsonEncode(c.qaSnapshot()));
      out.writeln('stored ${(await c.storedRide())?.rideId}');
    });
    _expectTrace('rider_finding_driver_controller_timeout', trace);
  });
}
