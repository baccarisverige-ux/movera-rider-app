// rider-u78: the server refuses a profile name over 80 characters, but
// sign-up allowed 40 + 1 + 40 = 81 and the Personal info editor had no
// limit at all.
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/auth/presentation/rider_name.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('the limit is the server contract\'s', () {
    expect(RiderProfileData.maxNameLength, 80);
  });

  testWidgets('Personal info keeps a name within 80 characters', (
    tester,
  ) async {
    phone(tester);
    final profile = ProfileController(
      store: ProfileRepository(storageKey: 'test_profile'),
    );
    final security = AccountSecurityController(
      repository: AccountSecurityRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.test,
            apiBaseUrl: 'https://api.test.movera.invalid',
          ),
          client: InProcessMockClient(),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalInfoPage(
          controller: profile,
          securityController: security,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'N' * 100);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(profile.profile.name, 'N' * 80);
  });

  testWidgets('sign-up first and last name together fit in 80 characters', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => const MaterialApp(home: RiderNameScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'F' * 60);
    await tester.enterText(fields.at(1), 'L' * 60);
    await tester.pump();

    String text(int i) =>
        tester.widget<EditableText>(fields.at(i)).controller.text;
    expect(
      '${text(0)} ${text(1)}'.length,
      lessThanOrEqualTo(RiderProfileData.maxNameLength),
    );
    // A first name keeps the 40 characters it always had.
    expect(text(0).length, 40);
    await tester.pumpWidget(const SizedBox());
  });
}
