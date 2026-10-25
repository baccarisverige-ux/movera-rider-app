import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The live server speaks the contract: GET answers the bare `Rider`, PATCH
/// takes `RiderProfileUpdate` with `expectedVersion` and `firstName`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const env = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );

  http.Response json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> rider(int version, {String firstName = 'Sara'}) => {
    'riderId': 'rdr_1',
    'firstName': firstName,
    'status': 'active',
    'version': version,
    'language': 'sv',
    'consents': {'rideUpdates': true},
  };

  test('reads the bare Rider and sends firstName with its version', () async {
    final patches = <Map<String, dynamic>>[];
    final repo = SyncedProfileRepository(
      api: ApiClient(
        env: env,
        tokens: MemoryTokenStore(),
        client: MockClient((request) async {
          if (request.method == 'GET') return json(rider(3));
          patches.add(jsonDecode(request.body) as Map<String, dynamic>);
          return json(rider(4, firstName: 'Sara B'));
        }),
      ),
    );

    await repo.hydrate();
    expect(repo.current.name, 'Sara');
    await repo.save(repo.current.copyWith(name: 'Sara B'));
    await repo.save(repo.current.copyWith(promotions: true));

    expect(patches[0]['expectedVersion'], 3);
    expect(patches[0]['firstName'], 'Sara B');
    expect(patches[0].containsKey('name'), isFalse);
    expect(patches[1]['expectedVersion'], 4);
  });

  test('a version mismatch re-reads the version and sends once more', () async {
    final patches = <Map<String, dynamic>>[];
    var reads = 0;
    final repo = SyncedProfileRepository(
      api: ApiClient(
        env: env,
        tokens: MemoryTokenStore(),
        client: MockClient((request) async {
          if (request.method == 'GET') return json(rider(++reads == 1 ? 1 : 2));
          patches.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (patches.length == 1) {
            return json({
              'code': 'version_mismatch',
              'message': 'Stale.',
              'requestId': 'r',
              'retryable': false,
            }, 409);
          }
          return json(rider(3));
        }),
      ),
    );

    await repo.hydrate();
    await repo.save(repo.current.copyWith(promotions: true));

    expect(patches.map((p) => p['expectedVersion']), [1, 2]);
    expect(repo.syncPending, isFalse);
  });
}
