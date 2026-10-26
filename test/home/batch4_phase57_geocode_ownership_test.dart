import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/location/app_geocoding.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';

class _Tokens implements TokenStore {
  @override
  Future<String?> readAccess() async => 'phase57-token';

  @override
  Future<String?> readRefresh() async => null;

  @override
  Future<void> save({required String access, required String refresh}) async {}

  @override
  Future<void> clear() async {}
}

class _ControlledGeo extends AppGeocoding {
  final Completer<void> slowStarted = Completer<void>();
  final Completer<void> releaseSlow = Completer<void>();

  @override
  Future<PlaceResult?> forward(String address) async {
    if (address == 'Slow pickup') {
      if (!slowStarted.isCompleted) slowStarted.complete();
      await releaseSlow.future;
      return const PlaceResult(
        address: 'Normalized slow pickup',
        point: GeoPoint(59.31, 18.01),
      );
    }
    return const PlaceResult(
      address: 'Normalized destination',
      point: GeoPoint(59.34, 18.08),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'independent Home geocode operations do not invalidate one another',
    () async {
      final geo = _ControlledGeo();
      final controller = HomeLocationController(
        location: LocationRepository(),
        geocoding: geo,
        motion: MotionEngine(),
      );
      addTearDown(controller.dispose);

      final pickup = controller.normaliseAddress('Slow pickup');
      await geo.slowStarted.future;

      final destination = await controller.geocodeLatLng('Destination');
      expect(destination?.latitude, 59.34);

      geo.releaseSlow.complete();
      expect(
        await pickup,
        'Normalized slow pickup',
        reason:
            'map-point geocoding must not mark an independent address normalization stale',
      );
    },
  );

  test(
    'AppGeocoding preserves every distinct concurrent forward request',
    () async {
      var calls = 0;
      final httpClient = MockClient((request) async {
        calls += 1;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        if (query == 'Pickup') {
          await Future<void>.delayed(const Duration(milliseconds: 35));
        } else if (query == 'Destination') {
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
        return http.Response(
          jsonEncode({
            'data': {
              'address': 'Normalized $query',
              'latitude': 59.3 + calls / 1000,
              'longitude': 18.0 + calls / 1000,
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

      final results = await Future.wait([
        geocoding.forward('Pickup'),
        geocoding.forward('Destination'),
        geocoding.forward('Stop 1'),
        geocoding.forward('Stop 2'),
      ]);

      expect(calls, 4);
      expect(
        results.map((result) => result?.address).toList(),
        const [
          'Normalized Pickup',
          'Normalized Destination',
          'Normalized Stop 1',
          'Normalized Stop 2',
        ],
        reason:
            'distinct route addresses are independent work and must not invalidate one another',
      );
    },
  );
}
