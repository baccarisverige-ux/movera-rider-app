import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';

/// D2 (R11-23): when the app comes back to the front the settings stream
/// is opened again (a socket kept in the background may be dead without
/// an error), but a reconnect already waiting keeps its backoff.
void main() {
  ({
    ApiRiderConfigRepository repo,
    List<Duration> opens,
    void Function(bool) refuse,
  })
  build(FakeAsync async) {
    final opens = <Duration>[];
    var refuse = false;
    final client = MockClient.streaming((request, _) async {
      if (request.url.path.endsWith('/stream')) {
        opens.add(async.elapsed);
        return refuse
            ? http.StreamedResponse(Stream.value(utf8.encode('{}')), 503)
            // Open and silent, like a socket that died in the background.
            : http.StreamedResponse(StreamController<List<int>>().stream, 200);
      }
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    });
    final repo = ApiRiderConfigRepository(
      api: ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.movera.invalid',
        ),
        client: client,
        tokens: MemoryTokenStore()..save(access: 'a', refresh: 'r'),
      ),
      cache: MemoryRiderConfigCache(),
      random: math.Random(7),
    );
    return (repo: repo, opens: opens, refuse: (v) => refuse = v);
  }

  test('resume opens the settings stream again', () {
    fakeAsync((async) {
      final t = build(async);
      t.repo.watch('Z001');
      async.elapse(const Duration(seconds: 1));
      expect(t.opens, hasLength(1));
      t.repo.resumeWatch();
      async.elapse(const Duration(seconds: 1));
      expect(t.opens, hasLength(2));
      t.repo.dispose();
    });
  });

  test('resume keeps a waiting reconnect (backoff)', () {
    fakeAsync((async) {
      final t = build(async);
      t.refuse(true);
      t.repo.watch('Z001');
      async.elapse(const Duration(seconds: 1));
      expect(t.opens, hasLength(1));
      t.repo.resumeWatch();
      async.elapse(const Duration(seconds: 1));
      expect(t.opens, hasLength(1), reason: 'the 5 s backoff wait stands');
      t.repo.dispose();
    });
  });
}
