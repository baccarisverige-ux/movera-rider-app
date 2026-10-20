import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CODE-17: one corrupt entry in the pending-cancel outbox used to make every
/// read throw, so no later cancel could be queued, found, removed or flushed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const outboxKey = 'movera_pending_cancels';
  final valid = jsonEncode({
    'rideId': 'r-ok',
    'reasonId': null,
    'idempotencyKey': 'ride-cancel-ok',
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      outboxKey: <String>['{}', 'not json', '[1,2]', '{"rideId":7}', valid],
    });
  });

  test('corrupt entries are skipped when reading the outbox', () async {
    final all = await PendingCancelStore.all();
    expect(all.map((entry) => entry.rideId), ['r-ok']);
    expect(all.single.idempotencyKey, 'ride-cancel-ok');
    expect((await PendingCancelStore.find('r-ok'))?.rideId, 'r-ok');
  });

  test(
    'enqueue still records a new cancel and drops the bad entries',
    () async {
      final entry = await PendingCancelStore.enqueue(rideId: 'r-new');
      expect(entry.idempotencyKey, isNotNull);

      final all = await PendingCancelStore.all();
      expect(all.map((entry) => entry.rideId), ['r-ok', 'r-new']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(outboxKey), hasLength(2));
    },
  );

  test('remove works with corrupt entries present', () async {
    await PendingCancelStore.remove('r-ok');
    expect(await PendingCancelStore.all(), isEmpty);
  });

  test('the flush still sends the readable entries', () async {
    final backend = InProcessMockClient();
    backend.rides['r-ok'] = {'id': 'r-ok', 'status': 'findingDriver'};

    await FindingDriverController.flushPendingCancels(
      api: ApiClient(client: backend),
    );

    expect(backend.rides['r-ok']!['status'], 'cancelled_by_rider');
    expect(await PendingCancelStore.all(), isEmpty);
  });
}
