import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/features/destination_search/data/place_suggestion_repository.dart';

/// Same-address fix (contract v0.18.44 §67). Proven case (Rules
/// plan/FIX-PLAN-RERUN-2026-11-05.md "Proof: same-address booking"): the
/// rider picked "Solna Centrum" / "Solnavägen, Solna, Sverige"; the app sent
/// only the text to /locations/geocode and replaced the chosen label with
/// the answer's street address "Solnavägen 13, 171 45 Solna, Sverige".
class _Tokens implements TokenStore {
  @override
  Future<String?> readAccess() async => 'token';
  @override
  Future<String?> readRefresh() async => null;
  @override
  Future<void> save({required String access, required String refresh}) async {}
  @override
  Future<void> clear() async {}
}

const _chosen = 'Solna Centrum, Solnavägen, Solna, Sverige';
const _street = 'Solnavägen 13, 171 45 Solna, Sverige';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a picked suggestion keeps its name and is geocoded by its placeId',
    () async {
      final geocodeBodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        if (request.url.path == '/api/v1/locations/autocomplete') {
          return http.Response(
            jsonEncode({
              'suggestions': [
                {
                  'title': 'Solna Centrum',
                  'subtitle': 'Solnavägen, Solna, Sverige',
                  'placeId': 'ChIJSolna',
                },
              ],
            }),
            200,
          );
        }
        geocodeBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'name': 'Solna Centrum',
            'address': _street,
            'latitude': 59.3596729,
            'longitude': 18.0005394,
            'placeId': 'ChIJSolna',
          }),
          200,
        );
      });
      final api = ApiClient(
        client: client,
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://api.movera.test',
        ),
        tokens: _Tokens(),
      );
      final picked = (await PlaceSuggestionRepository(
        api,
      ).suggest('solna c')).single;
      expect(picked.address, _chosen);

      final result = await AppGeocoding(api: api).forward(picked.address);
      expect(geocodeBodies.single, {'query': _chosen, 'placeId': 'ChIJSolna'});
      expect(
        result?.address,
        _chosen,
        reason: 'the chosen label stays, never the street address',
      );
      expect(result?.point.latitude, 59.3596729);
    },
  );

  test(
    'typed text with no suggestion still takes the geocoded address',
    () async {
      final client = MockClient((request) async {
        expect(jsonDecode(request.body), {'query': 'sergels'});
        return http.Response(
          jsonEncode({
            'address': 'Sergels torg, Stockholm',
            'latitude': 59.33,
            'longitude': 18.06,
          }),
          200,
        );
      });
      final api = ApiClient(
        client: client,
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://api.movera.test',
        ),
        tokens: _Tokens(),
      );
      expect(
        (await AppGeocoding(api: api).forward('sergels'))?.address,
        'Sergels torg, Stockholm',
      );
    },
  );
}
