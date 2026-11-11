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
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';

/// E15: the server closes `/rider/config/stream` when its LISTEN connection
/// reconnects; `rider_trip_changed` hints in the gap are lost. The rider
/// reads the booked rides and the active trip again after every reconnect
/// (not on the first connect, which `start()` already covers).
void main() {
  test('every stream reconnect re-reads booked rides and the active trip', () {
    fakeAsync((async) {
      var opens = 0;
      final client = MockClient.streaming((request, _) async {
        if (request.url.path.endsWith('/stream')) {
          opens++;
          // The server closes the stream at once (LISTEN reconnect).
          return http.StreamedResponse(const Stream.empty(), 200);
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
      final log = <String>[];
      final watch = RiderTripWatch(
        showsHome: () => true,
        adopt: () async => log.add('adopt'),
        bookedOnTheWay: () async => false,
        refreshBooked: () async => log.add('refresh'),
        pollEvery: const Duration(hours: 1),
      );
      repo.reconnectTaps.add(watch.onStreamReconnected);
      repo.watch('Z001');
      async.flushMicrotasks();
      expect(opens, 1);
      expect(log, isEmpty, reason: 'first connect reads nothing extra');
      async.elapse(const Duration(seconds: 6));
      expect(opens, 2);
      expect(log.where((e) => e == 'refresh'), hasLength(1));
      expect(log.where((e) => e == 'adopt'), hasLength(1));
      async.elapse(const Duration(seconds: 6));
      expect(opens, 3);
      expect(log.where((e) => e == 'refresh'), hasLength(2));
      expect(log.where((e) => e == 'adopt'), hasLength(2));
      repo.dispose();
    });
  });
}
