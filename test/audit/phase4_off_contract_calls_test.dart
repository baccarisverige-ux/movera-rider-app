import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/promotions/data/rider_promotion_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_catalog_cache.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';

/// Audit Phase 4: on the contract wire (staging, production) the rider app
/// no longer calls `GET /ride-types` and `GET /rider/promotions/active`,
/// which are not in the contract and which movera-server answers with 404.
/// The demo's in-process mock keeps serving both.
void main() {
  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );
  const demo = AppEnv(flavor: AppFlavor.demo, apiBaseUrl: 'https://x.invalid');

  ({ApiClient api, List<String> paths}) recording(AppEnv env) {
    final paths = <String>[];
    final api = ApiClient(
      env: env,
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          '{"rideTypes":[],"promotion":null}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (api: api, paths: paths);
  }

  test(
    'live: the ride list comes from the built-in list, no request',
    () async {
      final r = recording(live);
      final catalog = RideCatalogController(
        api: r.api,
        cache: MemoryRideCatalogCache(),
      );
      final items = await catalog.load();
      expect(r.paths, isEmpty);
      expect(catalog.source, RideCatalogSource.builtIn);
      expect(items, RideSelectionRepository.builtInRides);
    },
  );

  test('live: no promotion and no request', () async {
    final r = recording(live);
    expect(await RiderPromotionRepository(r.api).fetchActive(), isNull);
    expect(r.paths, isEmpty);
  });

  test('demo: both are still asked from the mock', () async {
    final r = recording(demo);
    await RideCatalogController(
      api: r.api,
      cache: MemoryRideCatalogCache(),
    ).load();
    await RiderPromotionRepository(r.api).fetchActive();
    expect(r.paths, ['/api/v1/ride-types', '/api/v1/rider/promotions/active']);
  });
}
