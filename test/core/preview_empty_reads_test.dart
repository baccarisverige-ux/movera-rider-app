import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/preview/preview_mode.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:movera_rider/features/ride_booking/data/active_trip_repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Owner 2026-11-04 (B7 "B: Empty screens"): with a preview token the server
// answers the rider's own reads with a brand-new account's empty result
// (movera-server test/config/preview_reads.test.ts). Every read parses.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ApiClient api() => ApiClient(
    client: MockClient((request) async {
      switch (request.url.path) {
        case '/api/v1/rider/profile':
          return http.Response(
            jsonEncode({
              'riderId': 'preview:rider:Z001',
              'firstName': '',
              'status': 'active',
              'version': 1,
              'rating': null,
              'outstanding': null,
              'outstandingByCurrency': <Object>[],
            }),
            200,
          );
        case '/api/v1/rider/trips/active':
          return http.Response('', 204);
        default:
          return http.Response('{"items":[],"nextCursor":null}', 200);
      }
    }),
    env: const AppEnv(
      flavor: AppFlavor.staging,
      apiBaseUrl: 'https://api.test',
    ),
    tokens: PreviewTokenStore('a.b.c'),
    preview: const PreviewMode(token: 'a.b.c', zoneId: 'Z001'),
  );

  test(
    'blank profile and no active trip: no error, nothing invented',
    () async {
      final profile = SyncedProfileRepository(api: api());
      await profile.hydrate();
      expect(profile.serverKnown, isTrue);
      expect(profile.current.name.trim(), isEmpty);
      expect(await ApiActiveTripRepository(api: api()).fetchActive(), isNull);
      expect(await api().get('/api/v1/rider/trips'), {
        'items': <Object>[],
        'nextCursor': null,
      });
    },
  );
}
