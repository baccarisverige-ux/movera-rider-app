import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/profile/presentation/account_checkup.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/features/profile/presentation/privacy.dart';
import 'package:movera_rider/features/profile/presentation/security.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProfileController controller({String storageKey = 'test_profile'}) {
    return ProfileController(
      store: ProfileRepository(storageKey: storageKey),
    );
  }

  AccountSecurityController securityController() {
    const env = AppEnv(
      flavor: AppFlavor.test,
      apiBaseUrl: 'https://api.test.movera.invalid',
    );
    final client = InProcessMockClient();
    client.accountSecurity
      ..['phone'] = '+46701234567'
      ..['email'] = 'rider@example.test'
      ..['phoneVerifiedAt'] = null
      ..['emailVerifiedAt'] = '2026-01-01T12:00:00.000Z'
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
    return AccountSecurityController(
      repository: AccountSecurityRepository(
        api: ApiClient(
          env: env,
          client: client,
        ),
      ),
    );
  }

  Future<void> pumpPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: home));
  }

  test('fresh profile contains no seeded rider identity', () {
    final profile = RiderProfileData.defaults();
    expect(profile.name, isEmpty);
    expect(profile.email, isEmpty);
    expect(profile.phone, isEmpty);
    expect(profile.photoAsset, isEmpty);
    expect(profile.appleConnected, isFalse);
    expect(profile.logins, isEmpty);
    expect(profile.passwordUpdatedAt.millisecondsSinceEpoch, 0);
  });

  test('legacy demo identity is removed without inventing a replacement', () async {
    const key = 'legacy_profile';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({
        'name': 'Ben Gleason',
        'email': 'ben.gleason@movera.se',
        'phone': '+46 70 123 45 67',
        'gender': 'Man',
        'language': 'English',
        'photoAsset': 'assets/images/profile_img.webp',
        'passwordUpdatedAt': '2025-11-04T00:00:00.000',
        'appleConnected': true,
        'logins': [
          {
            'device': 'This browser',
            'place': 'Stockholm, Sweden',
            'source': 'Movera Web',
            'current': true,
          },
          {
            'device': 'iPhone',
            'place': 'Stockholm, Sweden',
            'source': 'Movera iOS',
            'current': false,
          },
        ],
      }),
    });

    final c = controller(storageKey: key);
    await c.hydrate();

    expect(c.profile.name, isEmpty);
    expect(c.profile.email, isEmpty);
    expect(c.profile.phone, isEmpty);
    expect(c.profile.gender, '');
    expect(c.profile.photoAsset, isEmpty);
    expect(c.profile.appleConnected, isFalse);
    expect(c.profile.logins, isEmpty);
    expect(c.displayName(), 'Welcome to Movera');

    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
    expect(persisted['name'], '');
    expect(persisted.containsKey('email'), isFalse);
    expect(persisted.containsKey('phone'), isFalse);
    expect(persisted['gender'], '');
    expect(persisted['photoAsset'], '');
    expect(persisted.containsKey('appleConnected'), isFalse);
    expect(persisted.containsKey('logins'), isFalse);
  });

  test('only presentation profile edits survive local hydration', () async {
    const key = 'real_profile';
    final first = controller(storageKey: key);
    await first.update(
      RiderProfileData.defaults().copyWith(
        name: 'Real Rider',
        email: 'real.rider@example.com',
        phone: '+46 70 999 88 77',
      ),
    );

    final second = controller(storageKey: key);
    await second.hydrate();

    expect(second.profile.name, 'Real Rider');
    expect(second.profile.email, isEmpty);
    expect(second.profile.phone, isEmpty);
  });

  testWidgets('account hub shows authoritative account email state', (tester) async {
    final security = securityController();
    await security.load();
    await pumpPhone(
      tester,
      AccountHomePage(
        controller: controller(),
        securityController: security,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Personal info'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIconAsset && w.asset == AppAssets.solarUserRounded,
      ),
      findsWidgets,
    );
    expect(find.text('Add your name'), findsOneWidget);
    expect(find.text('rider@example.test · Verified'), findsOneWidget);
    expect(find.text('Name, phone, email, language'), findsOneWidget);
    expect(find.text('Ben Gleason'), findsNothing);
    expect(find.textContaining('Uber'), findsNothing);
  });

  testWidgets('personal info uses server contact truth and edits only presentation data', (tester) async {
    final c = controller();
    final security = securityController();
    await pumpPhone(
      tester,
      PersonalInfoPage(
        controller: c,
        securityController: security,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('+46701234567 · Not verified'), findsOneWidget);
    expect(find.text('rider@example.test · Verified'), findsOneWidget);
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Houssem Baccari');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.profile.name, 'Houssem Baccari');
  });

  testWidgets('security is server-backed and unsupported controls are read-only', (
    tester,
  ) async {
    final security = securityController();
    await pumpPhone(
      tester,
      SecurityPage(securityController: security),
    );
    await tester.pumpAndSettle();

    expect(find.text('Passkeys'), findsOneWidget);
    expect(find.text('2-step verification'), findsOneWidget);
    expect(
      find.text('Coming soon'),
      findsWidgets,
    );
    expect(find.byType(Switch), findsNothing);

    final otherDevice = find.text('Other device');
    await tester.scrollUntilVisible(otherDevice, 300);
    await tester.pumpAndSettle();
    expect(otherDevice, findsOneWidget);
    expect(find.textContaining('Stockholm, Sweden'), findsWidgets);

    final signOut = find.text('Sign out other devices');
    await tester.scrollUntilVisible(signOut, 300);
    await tester.pumpAndSettle();
    expect(signOut, findsOneWidget);
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
    expect(security.state!.sessions.any((item) => !item.current), isTrue);
  });

  testWidgets('Account Check ignores local contact strings for verification', (
    tester,
  ) async {
    final profile = controller();
    await profile.update(
      RiderProfileData.defaults().copyWith(
        phone: '+46709999999',
        email: 'local@example.test',
      ),
    );
    final security = securityController();

    await pumpPhone(
      tester,
      AccountCheckupPage(
        controller: profile,
        securityController: security,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('+46701234567 · Not verified'), findsOneWidget);
    expect(find.textContaining('+46709999999'), findsNothing);
    expect(find.textContaining('Verified'), findsNothing);
  });

  testWidgets('privacy communication toggles persist', (tester) async {
    final c = controller();
    await pumpPhone(tester, PrivacyPage(controller: c));
    expect(find.text('Ride updates'), findsOneWidget);
    expect(find.text('Offers'), findsOneWidget);
    expect(c.profile.promotions, isFalse);
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    expect(c.profile.promotions, isTrue);
  });
}
