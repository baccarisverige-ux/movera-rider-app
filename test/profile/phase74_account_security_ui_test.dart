import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_checkup.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/features/profile/presentation/security.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  const env = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );

  Future<AccountSecurityController> securityController({
    bool reauthenticationSupported = false,
    bool freshlyReauthenticated = false,
  }) async {
    final client = InProcessMockClient();
    final capabilities = Map<String, dynamic>.from(
      client.accountSecurity['capabilities'] as Map,
    );
    capabilities
      ..['reauthentication'] = reauthenticationSupported
      ..['signOutOtherDevices'] = true;

    client.accountSecurity
      ..['phone'] = '+46701234567'
      ..['email'] = 'rider@example.test'
      ..['phoneVerifiedAt'] = null
      ..['emailVerifiedAt'] = '2026-01-01T12:00:00.000Z'
      ..['reauthenticatedAt'] = freshlyReauthenticated
          ? DateTime.now().toUtc().toIso8601String()
          : null
      ..['capabilities'] = capabilities
      ..['sessions'] = [
        {
          'id': 'session_current',
          'device': 'This device',
          'place': 'Stockholm, Sweden',
          'source': 'Movera',
          'current': true,
        },
        {
          'id': 'session_other',
          'device': 'Other device',
          'place': 'Stockholm, Sweden',
          'source': 'Movera',
          'current': false,
        },
      ];

    final controller = AccountSecurityController(
      repository: AccountSecurityRepository(
        api: ApiClient(env: env, client: client),
      ),
    );
    await controller.load();
    return controller;
  }

  Future<ProfileController> profileController() async {
    final controller = ProfileController(
      store: ProfileRepository(storageKey: 'phase74_ui_profile'),
    );
    await controller.hydrate();
    return controller;
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: child));
    await tester.pumpAndSettle();
  }

  testWidgets('unsupported security controls are read-only and truthful',
      (tester) async {
    final security = await securityController();
    await pump(
      tester,
      SecurityPage(securityController: security),
    );

    expect(
      find.text('Coming soon'),
      findsAtLeastNWidgets(5),
    );
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Connect'), findsNothing);
    expect(find.text('Disconnect'), findsNothing);

    final signOut = find.text('Sign out other devices');
    await tester.scrollUntilVisible(signOut, 300);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.ancestor(of: signOut, matching: find.byType(AccountTile)),
        matching: find.text('Coming soon'),
      ),
      findsOneWidget,
    );
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(find.text('Sign out others'), findsNothing);
  });

  testWidgets('Account Check uses server verification metadata', (tester) async {
    final security = await securityController();
    final profile = await profileController();
    await pump(
      tester,
      AccountCheckupPage(
        controller: profile,
        securityController: security,
      ),
    );

    expect(find.text('+46701234567 · Not verified'), findsOneWidget);
    expect(find.text('Unavailable'), findsAtLeastNWidgets(2));
  });

  testWidgets('Personal Info cannot locally edit phone or email',
      (tester) async {
    final security = await securityController();
    final profile = await profileController();
    await pump(
      tester,
      PersonalInfoPage(
        controller: profile,
        securityController: security,
      ),
    );

    expect(find.text('+46701234567 · Not verified'), findsOneWidget);
    expect(find.text('rider@example.test · Verified'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Phone'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('fresh reauth allows server-verified session revocation',
      (tester) async {
    final security = await securityController(
      reauthenticationSupported: true,
      freshlyReauthenticated: true,
    );
    await pump(
      tester,
      SecurityPage(securityController: security),
    );

    final otherDevice = find.text('Other device');
    await tester.scrollUntilVisible(otherDevice, 300);
    await tester.pumpAndSettle();
    expect(otherDevice, findsOneWidget);

    final signOut = find.text('Sign out other devices');
    await tester.scrollUntilVisible(signOut, 300);
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out others'));
    await tester.pumpAndSettle();

    expect(find.text('Other device'), findsNothing);
    expect(
      security.state!.sessions.every((session) => session.current),
      isTrue,
    );
  });
}
