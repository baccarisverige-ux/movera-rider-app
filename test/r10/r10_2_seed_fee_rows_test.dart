// Owner 2026-11-10 (R10, global plan step 73). Was a proof that failed
// before the fix because a live build merges the server's rider config
// over the built-in sample document: a category the server leaves out of
// `cancelFees.reservation` keeps the SAMPLE fee (AUDIT-R10 §3.2 item 1,
// R10 #2; `rider_app_config.dart:333-346`, `api_rider_config_repository.dart:134`).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/config/live_data_only.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RiderZones.useSamples();
    LiveDataOnly.on = true;
    ServerFeatures.clear();
  });
  tearDown(() {
    LiveDataOnly.on = false;
    RiderZones.useSamples();
    ServerFeatures.clear();
  });

  test('live: a fee row the server did not send is not shown', () async {
    // Recorded-shape server answer (contract fixture) without the
    // reservation premium row.
    final answer =
        jsonDecode(
              File(
                'contracts/fixtures/config/rider_app_config.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    ((answer['cancelFees'] as Map)['reservation'] as Map).remove('premium');

    final repo = ApiRiderConfigRepository(
      api: ApiClient(
        env: staging,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(answer),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
      cache: MemoryRiderConfigCache(),
      homeZoneId: answer['zoneId'] as String,
    );
    final served = await repo.currentServed();
    expect(repo.isServerDocument(served), isTrue);

    final rule = served.reservationFeeFor('premium');
    expect(
      rule,
      isNull,
      reason:
          'the server sent no reservation premium fee; a live build must '
          'not fill it from the sample document (got the sample rule: '
          '${rule?.type} ${rule?.value}, free until ${rule?.freeMin} min)',
    );
  });
}
