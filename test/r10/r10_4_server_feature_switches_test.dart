// Owner 2026-11-10 (R10, global plan step 73). Was a proof that failed
// before the fix because the admin/server `features.wallet / pin /
// shareTrip` switches in the rider config are parsed but never read
// (`rider_app_config.dart:301, 366`, 0 callers); the app's switches come
// only from the built-in FeatureFlags (`di.dart:106`,
// `feature_flags.dart:50-51`) and the wallet row from
// `ride_selection_controller.dart:326, 410`. AUDIT-R10 R10 #4.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/config/live_data_only.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  Future<RiderAppConfig> served(Map<String, bool> features) async {
    final answer =
        jsonDecode(
              File(
                'contracts/fixtures/config/rider_app_config.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    answer['features'] = {...(answer['features'] as Map), ...features};
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
    return repo.currentServed();
  }

  test('admin turns the wallet off: the live app follows', () async {
    final config = await served({'wallet': false});
    expect(config.feature('wallet'), isFalse);

    final flags = FeatureFlags.forEnvironment(staging);
    final selection = RideSelectionController(flags: flags);
    addTearDown(selection.dispose);
    selection.setWalletBalance(100);
    expect(
      selection.payments().map((p) => p.brand),
      isNot(contains('wallet')),
      reason: 'server said features.wallet=false; the wallet is still offered',
    );
  });

  test('admin turns PIN on and share-trip off: the live app follows', () async {
    final config = await served({'pin': true, 'shareTrip': false});
    final flags = FeatureFlags.forEnvironment(staging);
    expect(
      flags.enableRidePin,
      config.feature('pin'),
      reason: 'server said features.pin=true; the app keeps its own value',
    );
    expect(
      flags.safetyShareTrip,
      config.feature('shareTrip'),
      reason: 'server said features.shareTrip=false; app keeps its own value',
    );
  });
}
