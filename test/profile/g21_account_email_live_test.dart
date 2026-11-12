import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G21 (BrowserStack 2026-11-12, Tunis): on every live build the Account
/// card said "Impossible de récupérer l'adresse e-mail du serveur" and
/// "Statut de sécurité indisponible". The controller was composed with
/// built: false (no /account/security on movera-server), so load() never
/// asked anything and the state stayed null. The phone and e-mail are on
/// the rider's own profile (GET /rider/profile, contract Rider).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  (AccountSecurityController, List<String>) liveSecurity({
    Map<String, Object?>? rider,
    int status = 200,
  }) {
    final calls = <String>[];
    final controller = AccountSecurityController(
      built: false,
      readsRiderProfile: true,
      repository: AccountSecurityRepository(
        api: ApiClient(
          env: live,
          client: MockClient((request) async {
            calls.add('${request.method} ${request.url.path}');
            if (request.url.path != '/api/v1/rider/profile' || status != 200) {
              return http.Response(
                jsonEncode({'code': 'internal', 'message': 'down'}),
                status == 200 ? 404 : status,
              );
            }
            return http.Response(jsonEncode(rider), 200);
          }),
        ),
      ),
    );
    return (controller, calls);
  }

  Map<String, Object?> rider({String? email = 'ada@example.com'}) => {
    'riderId': 'rdr_1',
    'firstName': 'Ada',
    'phone': '+21620123456',
    'email': ?email,
    'status': 'active',
    'version': 3,
    'consents': <String, Object?>{},
  };

  Future<void> pumpPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, _) => MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProfileController profile(String key) =>
      ProfileController(store: ProfileRepository(storageKey: key));

  testWidgets('live: the Account card shows the e-mail from the rider '
      'profile, and no "security status unavailable"', (tester) async {
    final (security, calls) = liveSecurity(rider: rider());
    await pumpPhone(
      tester,
      AccountHomePage(
        controller: profile('g21_a'),
        securityController: security,
      ),
    );
    // G30 (contract v0.18.76): no emailVerifiedAt = Not verified.
    expect(
      find.text(L10n.current.valueNotVerified('ada@example.com')),
      findsOneWidget,
    );
    expect(find.text(L10n.current.serverEmailUnavailable), findsNothing);
    expect(find.text(L10n.current.securityStatusUnavailableDot), findsNothing);
    // Nothing to finish: the server offers neither 2-step nor recovery.
    expect(find.text(L10n.current.accountFinish), findsNothing);
    // Still no /account/security on the live wire (audit M3).
    expect(calls, ['GET /api/v1/rider/profile']);
    expect(find.text('Security'), findsNothing);
  });

  testWidgets('live: a rider without an e-mail reads "not added"', (
    tester,
  ) async {
    final (security, _) = liveSecurity(rider: rider(email: null));
    await pumpPhone(
      tester,
      AccountHomePage(
        controller: profile('g21_b'),
        securityController: security,
      ),
    );
    expect(find.text(L10n.current.emailNotAdded), findsOneWidget);
    expect(find.text(L10n.current.serverEmailUnavailable), findsNothing);
  });

  testWidgets('live: a failed read still shows the error', (tester) async {
    final (security, calls) = liveSecurity(status: 503);
    await pumpPhone(
      tester,
      AccountHomePage(
        controller: profile('g21_c'),
        securityController: security,
      ),
    );
    expect(calls, isNotEmpty);
    expect(find.text(L10n.current.serverEmailUnavailable), findsOneWidget);
    expect(
      find.text(L10n.current.securityStatusUnavailableDot),
      findsOneWidget,
    );
  });

  testWidgets('live: Personal info shows the phone alone (the profile has '
      'no phone date) and the e-mail with its G30 state', (tester) async {
    final (security, _) = liveSecurity(rider: rider());
    await pumpPhone(
      tester,
      PersonalInfoPage(
        controller: profile('g21_d'),
        securityController: security,
      ),
    );
    expect(find.text('+21620123456'), findsOneWidget);
    expect(
      find.text(L10n.current.valueNotVerified('+21620123456')),
      findsNothing,
    );
    // G30 (contract v0.18.76): no emailVerifiedAt = Not verified.
    expect(
      find.text(L10n.current.valueNotVerified('ada@example.com')),
      findsOneWidget,
    );
    expect(find.text(L10n.current.serverPhoneUnavailable), findsNothing);
    expect(find.text(L10n.current.serverEmailStatusUnavailable), findsNothing);
  });
}
