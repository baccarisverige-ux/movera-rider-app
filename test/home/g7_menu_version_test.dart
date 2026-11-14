// BQ-V46 (G7, REMINDERS 42). Owner 2026-11-11 (set 2, "App version + build
// number inside both apps": "Yes, both apps (Rec.)",
// Rules decisions/session-2026-11-06.md:961): the app shows its real
// version and build number. The side menu showed its own hard-coded
// "Movera Rider v1.0.0"; now it reads the build (MOVERA_APP_VERSION, the
// same source as the Account "Version x (build)" line):
// "Movera Rider 1.4.0 (583)".
// Fail-before: the menu said "Movera Rider v1.0.0" whatever was installed.
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/profile/presentation/app_version_line.dart';
import 'package:movera_rider/l10n/l10n.dart';

void main() {
  tearDown(() => L10n.use('en'));

  test('the short version reads "1.4.0 (583)", "1.4.0", "dev"', () {
    expect(AppVersionLine.short('1.4.0+583'), '1.4.0 (583)');
    expect(AppVersionLine.short('1.4.0'), '1.4.0');
    expect(AppVersionLine.short('dev'), 'dev');
  });

  test('the menu line is the installed version and build number', () {
    final expected = {
      'en': 'Movera Rider 1.4.0 (583)',
      'sv': 'Movera Rider 1.4.0 (583)',
      'fr': 'Movera 1.4.0 (583)',
    };
    for (final MapEntry(key: lang, value: text) in expected.entries) {
      L10n.use(lang);
      expect(RiderMenuPage.versionText('1.4.0+583'), text, reason: lang);
      expect(
        RiderMenuPage.versionText('2.0.1'),
        text.replaceFirst('1.4.0 (583)', '2.0.1'),
        reason: lang,
      );
    }
  });

  test('a local build says "dev", never a version it is not', () {
    L10n.use('en');
    expect(RiderMenuPage.versionText('dev'), 'Movera Rider dev');
  });
}
