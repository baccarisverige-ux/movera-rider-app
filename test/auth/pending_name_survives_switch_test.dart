import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/application/pending_rider_name.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-r5-31: a new rider's pending-name marker survives the wipe of the
/// previous rider's data that runs as the new session starts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the name step is still owed after a rider switch', () async {
    SharedPreferences.setMockInitialValues({
      UserDataWipe.riderFingerprintKey: 'previous-rider',
    });
    final tokens = MemoryTokenStore();
    final api = ApiClient(
      tokens: tokens,
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'accessToken': 'a',
              'refreshToken': 'r',
              'isNewRider': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
          )),
    );
    final auth = AuthController(
      auth: AuthRepository(api: api, tokens: tokens),
    );

    await auth.verifyOtp(
      challenge: OtpChallenge(
        phone: '+46701234567',
        requestId: 'q',
        sessionId: 's',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        retryAfter: Duration.zero,
      ),
      code: '1234',
    );

    expect(await PendingRiderName.read(), isNotNull);
  });
}
