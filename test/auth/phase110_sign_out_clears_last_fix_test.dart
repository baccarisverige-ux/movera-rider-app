import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Batch 10 Phase 110 privacy follow-up: the app-persisted last good location
/// fix (a map-camera hint) must not survive the end of a session, so the next
/// person using a shared or handed-down phone never sees the previous rider's
/// last position.
///
/// Uses only pre-existing public APIs (AuthController.signOut, the composed
/// AppScope ApiClient session-expiry path and the prefs key), so it also runs
/// on the base commit, where it fails. Behavioural only: no source reading.
const _key = 'movera.location.last_good_fix.v1';
const _fix = '{"lat":59.3326,"lng":18.0649,"savedAt":"2026-09-27T10:00:00Z"}';
const _unrelatedKey = 'phase110.unrelated.pref';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // AppScope's SecureTokenStore talks to flutter_secure_storage on the
    // default (Android) test platform; give it the plugin's in-memory mock.
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{
      _key: _fix,
      _unrelatedKey: 'kept',
    });
  });

  Future<AuthController> signedIn(http.Client transport) async {
    final tokens = MemoryTokenStore();
    await tokens.save(
      access: 'mock-access-rider',
      refresh: 'mock-refresh-rider',
    );
    return AuthController(
      auth: AuthRepository(
        api: ApiClient(client: transport, tokens: tokens),
        tokens: tokens,
      ),
    );
  }

  test('sign-out wipes the persisted last good location fix', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key), _fix, reason: 'precondition');

    final auth = await signedIn(
      MockClient((request) async => http.Response('{"code":"OK"}', 200)),
    );
    await auth.signOut();

    final after = await SharedPreferences.getInstance();
    expect(
      after.getString(_key),
      isNull,
      reason: 'the next rider on this device must not inherit the last fix',
    );
    expect(after.getString(_unrelatedKey), 'kept');
    expect(await auth.hasSession(), isFalse);
  });

  test(
    'sign-out wipes the last good fix even when the backend sign-out fails',
    () async {
      final auth = await signedIn(
        MockClient((request) async => http.Response('{"code":"DOWN"}', 503)),
      );
      await expectLater(auth.signOut(), throwsA(isA<ApiError>()));

      final after = await SharedPreferences.getInstance();
      expect(after.getString(_key), isNull);
      expect(await auth.hasSession(), isFalse);
    },
  );

  test(
    'session expiry (forced sign-out in the composed app) wipes the last good fix',
    () async {
      // A request that carried an access token gets 401 and the refresh token
      // is rejected: the composed ApiClient clears the session and runs the
      // AppScope onSessionExpired handler (the only sign-out reachable today).
      await AppScope.instance.tokens.save(
        access: 'phase110-expired-access',
        refresh: 'phase110-rejected-refresh',
      );
      await expectLater(
        AppScope.instance.api.post(
          '/api/v1/auth/refresh',
          body: {'refreshToken': 'phase110-rejected-refresh'},
        ),
        throwsA(
          isA<ApiError>().having((error) => error.statusCode, 'status', 401),
        ),
      );
      expect(await AppScope.instance.tokens.readAccess(), isNull);

      final after = await SharedPreferences.getInstance();
      expect(after.getString(_key), isNull);
      expect(after.getString(_unrelatedKey), 'kept');
    },
  );
}
