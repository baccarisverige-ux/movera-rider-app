import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

class _Tokens implements TokenStore {
  @override
  Future<String?> readAccess() async => 'private-token';
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> save({required String access, required String refresh}) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'forward geocoding uses authenticated Movera API and caches duplicates',
    () async {
      var calls = 0;
      final httpClient = MockClient((request) async {
        calls += 1;
        expect(request.url.host, 'api.movera.test');
        expect(request.url.path, '/api/v1/locations/geocode');
        expect(request.headers['Authorization'], 'Bearer private-token');
        expect(jsonDecode(request.body)['query'], 'Stockholm Central');
        return http.Response(
          jsonEncode({
            'data': {
              'address': 'Stockholm Central',
              'latitude': 59.330,
              'longitude': 18.058,
            },
          }),
          200,
        );
      });
      final api = ApiClient(
        client: httpClient,
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://api.movera.test',
        ),
        tokens: _Tokens(),
      );
      final geocoding = AppGeocoding(api: api);
      final first = await geocoding.forward('Stockholm Central');
      final second = await geocoding.forward(' Stockholm Central ');
      expect(first?.point.latitude, 59.330);
      expect(second?.address, 'Stockholm Central');
      expect(calls, 1);
    },
  );

  test(
    'reverse geocoding deduplicates an in-flight coordinate request',
    () async {
      var calls = 0;
      final httpClient = MockClient((request) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(
          jsonEncode({
            'data': {'address': 'Sveavägen'},
          }),
          200,
        );
      });
      final api = ApiClient(
        client: httpClient,
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://api.movera.test',
        ),
        tokens: _Tokens(),
      );
      final geocoding = AppGeocoding(api: api);
      const point = GeoPoint(59.334, 18.063);
      final results = await Future.wait([
        geocoding.reverse(point),
        geocoding.reverse(point),
      ]);
      expect(results.where((value) => value == 'Sveavägen').length, 2);
      expect(calls, 1);
    },
  );

  test(
    'reverse geocoding retries a missing address instead of caching null',
    () async {
      var calls = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'data': {'address': calls == 1 ? null : 'Sveavägen'},
            }),
            200,
          );
        }),
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://api.movera.test',
        ),
        tokens: _Tokens(),
      );
      final geo = AppGeocoding(api: api);
      const point = GeoPoint(59.334, 18.063);
      expect(await geo.reverse(point), isNull);
      expect(await geo.reverse(point), 'Sveavägen');
      expect(calls, 2);
    },
  );
}
