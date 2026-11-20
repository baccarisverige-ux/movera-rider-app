// Contract v0.18.148 (sosPressTime; owner 2026-11-20 "SOS kept and retried;
// after 30 min or any refusal ... SOS not sent, call 112"): the rider's SOS
// is kept on the phone with its press time `at` and sent again with the same
// Idempotency-Key and body until Movera takes it (also after the trip
// ended), refuses it, or it is 30 min old. A refusal or the age limit tells
// the rider "SOS not sent, call 112".
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/safety/data/sos_sender.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );
  final t0 = DateTime.utc(2026, 11, 20, 12);
  final at = t0.toIso8601String();

  late List<http.Request> posts;
  late bool networkUp;
  late int status;
  late String? reason;
  late int told;

  ApiClient api() => ApiClient(
    env: staging,
    client: MockClient((request) async {
      posts.add(request);
      if (!networkUp) throw http.ClientException('offline');
      return http.Response(
        jsonEncode(
          status == 200
              ? {'incidentId': 'inc_1', 'tripId': 'trp_1', 'receivedAt': at}
              : {
                  'code': status == 409 ? 'invalid_transition' : 'forbidden',
                  'message': 'x',
                  'requestId': 'r',
                  'retryable': false,
                  'reason': ?reason,
                },
        ),
        status,
      );
    }),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    posts = [];
    networkUp = false;
    status = 200;
    reason = null;
    told = 0;
    SosSender.onGivenUp = () => told++;
  });
  tearDown(SosSender.resetForTesting);

  test(
    'a press without network is kept and sent again with the same key and body until Movera has it',
    () async {
      var waits = 0;
      final sender = SosSender(
        api(),
        clock: () => t0,
        sleep: (_) async {
          // The network comes back during the background retries.
          if (++waits == 5) networkUp = true;
        },
      );
      await expectLater(sender.send('trp_1'), throwsA(anything));
      await sender.retryPending();
      expect(
        posts.map((r) => r.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(posts.map((r) => r.body).toSet(), hasLength(1));
      expect(jsonDecode(posts.first.body), {'at': '2026-11-20T12:00:00.000Z'});
      expect(await const PendingSosStore().read(), isNull);
      expect(told, 0);
    },
  );

  test(
    'after a restart the kept SOS goes out once the trip has ended (taken by its press time)',
    () async {
      await const PendingSosStore().save(
        PendingSos(key: 'sos-k1', tripId: 'trp_9', body: {'at': at}),
      );
      networkUp = true;
      await SosSender(
        api(),
        clock: () => t0.add(const Duration(minutes: 10)),
        sleep: (_) async {},
      ).retryPending();
      expect(posts.single.url.path, '/api/v1/rider/trips/trp_9/sos');
      expect(posts.single.headers['Idempotency-Key'], 'sos-k1');
      expect(jsonDecode(posts.single.body), {'at': at});
      expect(await const PendingSosStore().read(), isNull);
      expect(told, 0);
    },
  );

  test('any refusal of the kept SOS is final: dropped and told', () async {
    for (final refusal in [
      (409, 'sos_too_old'),
      (409, 'sos_not_during_trip'),
      (403, null),
    ]) {
      posts = [];
      told = 0;
      await const PendingSosStore().save(
        PendingSos(key: 'sos-k2', tripId: 'trp_9', body: {'at': at}),
      );
      networkUp = true;
      status = refusal.$1;
      reason = refusal.$2;
      await SosSender(
        api(),
        clock: () => t0.add(const Duration(minutes: 10)),
        sleep: (_) async => throw StateError('no retry after a refusal'),
      ).retryPending();
      expect(posts, hasLength(1), reason: '$refusal');
      expect(told, 1, reason: '$refusal');
      expect(await const PendingSosStore().read(), isNull);
    }
  });

  test('30 min after the press: not sent any more, dropped and told', () async {
    await const PendingSosStore().save(
      PendingSos(key: 'sos-k3', tripId: 'trp_9', body: {'at': at}),
    );
    networkUp = true;
    await SosSender(
      api(),
      clock: () => t0.add(const Duration(minutes: 31)),
      sleep: (_) async {},
    ).retryPending();
    expect(posts, isEmpty);
    expect(told, 1);
    expect(await const PendingSosStore().read(), isNull);
  });

  test(
    'a press refused as not live (no driver yet) is false and not kept; another refusal is told',
    () async {
      networkUp = true;
      status = 409;
      reason = 'trip_not_live';
      expect(await SosSender(api(), clock: () => t0).send('trp_1'), isFalse);
      await SosSender.writesDone;
      expect(await const PendingSosStore().read(), isNull);
      expect(told, 0);
      reason = 'sos_at_in_future';
      expect(await SosSender(api(), clock: () => t0).send('trp_1'), isFalse);
      await SosSender.writesDone;
      expect(told, 1);
    },
  );

  test('sign-out stops the retries and tells a kept SOS as not sent', () async {
    await const PendingSosStore().save(
      PendingSos(key: 'sos-k4', tripId: 'trp_9', body: {'at': at}),
    );
    await SosSender.signedOut();
    expect(told, 1);
    expect(PendingSosStore.prefKey, startsWith('movera_'));
  });
}
