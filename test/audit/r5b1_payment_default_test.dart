import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/payments/data/api_payment_method_repository.dart';

void main() {
  test('rider-r5-28: a newer default that saved replaces an older one that '
      'did not', () async {
    var server = 'cash';
    var failNext = true;
    final api = ApiClient(
      env: const AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://x.invalid'),
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          if (failNext) {
            failNext = false;
            return http.Response('{"code":"unavailable"}', 503);
          }
          server = jsonDecode(request.body)['methodId'] as String;
        }
        return http.Response(
          jsonEncode({'code': 'OK', 'methods': [], 'defaultMethodId': server}),
          200,
        );
      }),
    );
    final repo = ApiPaymentMethodRepository(api: api);
    await repo.save('google_pay');
    await repo.save('wallet');
    expect(await repo.read(), 'wallet');
    expect(server, 'wallet');
  });
}
