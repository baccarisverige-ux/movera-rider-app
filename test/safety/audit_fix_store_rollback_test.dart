// rider-r3-1: a failed Safety write restored a snapshot of the whole
// cache, wiping Ride check answers, events, recordings and contacts saved
// while it was in flight. It now rolls back only what it changed.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds Share trip on [gate] and then fails it; Ride check answers can
/// never be sent (offline).
class _FlakyClient extends InProcessMockClient {
  final gate = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/share')) {
      await gate.future;
      throw http.ClientException('timed out', request.url);
    }
    if (path == '/api/v1/safety/ridecheck/answers') {
      throw http.ClientException('offline', request.url);
    }
    return super.send(request);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSafetyMockForProcess();
  });

  test(
    'a failed Share trip keeps Ride check answers saved meanwhile',
    () async {
      final client = _FlakyClient();
      final local = PreferencesSafetyLocalDataSource(memoryOnly: true);
      final store = SafetyStore(
        local: local,
        remote: ApiSafetyRemoteDataSource(ApiClient(client: client)),
      );
      await store.load();

      final share = store.startShare('r1', contactIds: const []);
      await pumpEventQueue();

      // A Ride check is answered while the share waits; its send fails.
      final shownAt = DateTime.now().toUtc();
      await expectLater(
        store.submitRideCheckAnswers(
          RideCheckSubmission(
            checkId: 'rc_1',
            trigger: RideCheckTrigger.longStop,
            shownAt: shownAt,
            answers: [RideCheckAnswer.ok(shownAt)],
            context: const RideCheckTripContext(rideId: 'r1'),
            isFinal: true,
          ),
        ),
        throwsA(anything),
      );
      expect(await store.cachedRideCheckEvents('r1'), hasLength(1));

      client.gate.complete();
      await expectLater(share, throwsA(anything));

      final kept = await store.cachedRideCheckEvents('r1');
      expect(kept, hasLength(1), reason: 'the answers must stay on the trip');
      expect(kept.single.payload['answers'], isNotEmpty);
      final saved = (await local.load()).events.where(
        (e) => e.eventId == 'rc_1',
      );
      expect(saved, hasLength(1), reason: 'and in the saved copy');
      expect(
        await store.getShare('r1'),
        isNull,
        reason: 'the failed share itself is rolled back',
      );
    },
  );
}
