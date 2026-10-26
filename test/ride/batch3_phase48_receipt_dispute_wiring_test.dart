import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/ride_complete/application/ride_complete_controller.dart';
import 'package:movera_rider/features/ride_complete/data/ride_dispute_repository.dart';

class _Tokens implements TokenStore {
  @override
  Future<String?> readAccess() async => 'ride-token';
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
    'completed ride controller submits receipt dispute with auth and ride id',
    () async {
      late http.Request seen;
      final api = ApiClient(
        client: MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'status': 'submitted'}), 200);
        }),
        env: const AppEnv(
          flavor: AppFlavor.test,
          apiBaseUrl: 'https://api.movera.test',
        ),
        tokens: _Tokens(),
      );
      final controller = RideCompleteController(
        disputes: RideDisputeRepository(api: api),
      );

      await controller.submitDispute(
        rideId: 'ride-48',
        reason: 'receipt_issue',
        detail: 'Fare total looks wrong',
      );

      expect(seen.url.path, '/api/v1/rides/ride-48/disputes');
      expect(seen.headers['Authorization'], 'Bearer ride-token');
      expect(seen.headers['Idempotency-Key'], isNotEmpty);
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['reason'], 'receipt_issue');
      expect(body['detail'], 'Fare total looks wrong');
    },
  );
}
