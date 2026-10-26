import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/routing_service.dart';

void main() {
  test(
    'road routing uses Movera API contract and returns provider geometry',
    () async {
      const env = AppEnv(
        flavor: AppFlavor.test,
        apiBaseUrl: 'https://api.test.movera.invalid',
      );
      final api = ApiClient(client: InProcessMockClient(), env: env);
      final routing = RoutingService(api: api);
      const from = GeoPoint(59.3293, 18.0686);
      const to = GeoPoint(59.3326, 18.0649);

      final points = await routing.roadLine(from: from, to: to);

      expect(points, hasLength(2));
      expect(points.first.latitude, from.latitude);
      expect(points.last.longitude, to.longitude);
    },
  );

  test(
    'routing without configured provider falls back to direct line',
    () async {
      final routing = RoutingService();
      const from = GeoPoint(59.3, 18.0);
      const to = GeoPoint(59.4, 18.1);

      final points = await routing.roadLine(from: from, to: to);

      expect(points, [from, to]);
    },
  );
}
