import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _demo = AppEnv(
  flavor: AppFlavor.demo,
  apiBaseUrl: 'https://api.demo.movera.invalid',
);

/// The server profile says Swedish; signs in and reads it.
Future<InProcessMockClient> _signIn(AppLanguageController language) async {
  final server = InProcessMockClient()..riderProfile = {'language': 'sv'};
  final profile = ProfileController(
    store: SyncedProfileRepository(api: ApiClient(client: server, env: _demo)),
  );
  await profile.hydrateWithLanguage(language);
  return server;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rider-r5-42: a language picked on Sign in reaches the server '
      'profile', () async {
    final language = AppLanguageController();
    await language.choose('en');
    final server = await _signIn(language);
    expect(server.riderProfile?['language'], 'en');
  });
}
