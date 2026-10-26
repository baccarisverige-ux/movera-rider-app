import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('rider-r5-21: a cancel the outbox cannot store is still sent and '
      'reported unsent', () async {
    // Storage that throws on every outbox read and write.
    SharedPreferences.setMockInitialValues({'movera_pending_cancels': 'x'});
    var cancels = 0;
    final api = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://x.invalid',
      ),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/cancel')) cancels++;
        return http.Response(jsonEncode({'code': 'unavailable'}), 503);
      }),
    );
    final outcome = await ActiveRideController(api: api)
        .cancelUntrackedRide(rideId: 'ride_r5_21');
    expect(outcome, RideCancelOutcome.unsent);
    expect(cancels, greaterThan(0));
  });
}
