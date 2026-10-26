import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';

/// rider-r5-22: a failed refresh keeps the promotion already shown; only
/// the server saying "none" removes it. Runs on the demo wire: since audit
/// Phase 4 the contract wire never asks for promotions (not in the contract).
void main() {
  test('a failed lookup is not "no promotion"', () async {
    var up = true;
    Map<String, Object?>? promotion = {
      'id': 'p1',
      'title': '20% off your next 3 rides',
      'percentOff': 20,
      'ridesLeft': 3,
      'ridesTotal': 3,
      'endsAt': '2099-11-30T23:59:00Z',
    };
    final controller = RiderPromotionController(
      ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.demo,
          apiBaseUrl: 'https://x.invalid',
        ),
        client: MockClient(
          (_) async => up
              ? http.Response(
                  jsonEncode({'promotion': promotion}),
                  200,
                  headers: {'content-type': 'application/json'},
                )
              : http.Response('{"code":"bad_request"}', 400),
        ),
      ),
    );
    await controller.refresh();
    expect(controller.active, isNotNull);

    up = false;
    await controller.refresh();
    expect(controller.active, isNotNull);

    up = true;
    promotion = null;
    await controller.refresh();
    expect(controller.active, isNull);
  });
}
