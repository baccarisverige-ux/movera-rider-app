// Owner 2026-11-11 (set 2: "Yes, both apps"; contract v0.18.66 §87, app
// only, Rule 43(1)): the rider Account screen ends with the app version
// and build number, e.g. "Version 1.0.0 (583)", read from the build
// (MOVERA_APP_VERSION, the pubspec version with the APK's build number).
// Fail-before: no version line on the Account screen, no texts.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/profile/presentation/app_version_line.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    L10n.use('en');
  });

  testWidgets('the Account screen ends with the version line, under '
      'Delete account', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const env = AppEnv(
      flavor: AppFlavor.test,
      apiBaseUrl: 'https://api.test.movera.invalid',
    );
    final security = AccountSecurityController(
      repository: AccountSecurityRepository(
        api: ApiClient(env: env, client: InProcessMockClient()),
      ),
    );
    await security.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountHomePage(
          controller: ProfileController(
            store: ProfileRepository(storageKey: 'test_profile'),
          ),
          securityController: security,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final line = find.byKey(const ValueKey<String>('account-app-version'));
    await tester.scrollUntilVisible(line, 200);
    // A local / check build has no MOVERA_APP_VERSION: "Version dev".
    expect(
      tester.widget<Text>(line).data,
      matches(RegExp(r'^Version \S+( \(\S+\))?$')),
    );
    expect(
      tester.getTopLeft(line).dy,
      greaterThan(tester.getTopLeft(find.text('Delete account')).dy),
    );
  });

  test('a live build reads "Version 1.0.0 (583)"; no build number → '
      '"Version 1.0.0"; a local build "Version dev"', () {
    expect(AppVersionLine.text('1.0.0+583'), 'Version 1.0.0 (583)');
    expect(AppVersionLine.text('1.0.0'), 'Version 1.0.0');
    expect(AppVersionLine.text('dev'), 'Version dev');
  });

  test('the texts exist in sv / fr / en', () {
    for (final lang in ['sv', 'fr', 'en']) {
      L10n.use(lang);
      expect(AppVersionLine.text('1.0.0+583'), 'Version 1.0.0 (583)');
      expect(AppVersionLine.text('1.0.0'), 'Version 1.0.0');
    }
  });

  test('the test APK passes the real build number to the version line', () {
    final yml = File(
      '.github/workflows/android-test-apk.yml',
    ).readAsStringSync();
    expect(yml, contains(r'app_version="${app_version%%+*}+$number"'));
    expect(yml, contains(r'MOVERA_APP_VERSION="$app_version"'));
  });
}
