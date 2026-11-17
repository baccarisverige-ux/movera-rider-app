import 'dart:async';
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

/// G21 follow-up (2026-11-16): #597 made the Account card read
/// GET /rider/profile, but while that read is still on its way the card
/// already said "Impossible de récupérer l'adresse e-mail du serveur" and
/// "Statut de sécurité indisponible" (the state is null while loading). On
/// a slow phone network the rider saw the G21 errors on every first open.
/// An error is shown only after the read really failed.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  (AccountSecurityController, Completer<http.Response>) slowSecurity() {
    final answer = Completer<http.Response>();
    final controller = AccountSecurityController(
      built: false,
      readsRiderProfile: true,
      repository: AccountSecurityRepository(
        api: ApiClient(env: live, client: MockClient((_) => answer.future)),
      ),
    );
    return (controller, answer);
  }

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  final rider = jsonEncode({
    'riderId': 'rdr_1',
    'firstName': 'Ada',
    'phone': '+21620123456',
    'email': 'ada@example.com',
    'status': 'active',
    'version': 3,
    'consents': <String, Object?>{},
  });

  ProfileController profile(String key) =>
      ProfileController(store: ProfileRepository(storageKey: key));

  testWidgets('Account card: no error text while the profile is loading', (
    tester,
  ) async {
    final (security, answer) = slowSecurity();
    await pumpPhone(
      tester,
      AccountHomePage(
        controller: profile('g21_load_a'),
        securityController: security,
      ),
    );
    expect(security.loading, isTrue);
    expect(find.text(L10n.current.serverEmailUnavailable), findsNothing);
    expect(find.text(L10n.current.securityStatusUnavailableDot), findsNothing);
    expect(find.text(L10n.current.accountFinish), findsNothing);

    answer.complete(http.Response(rider, 200));
    await tester.pumpAndSettle();
    expect(
      find.text(L10n.current.valueNotVerified('ada@example.com')),
      findsOneWidget,
    );
    expect(find.text(L10n.current.serverEmailUnavailable), findsNothing);
  });

  testWidgets('Personal info: no "unavailable" while the profile is loading', (
    tester,
  ) async {
    final (security, answer) = slowSecurity();
    await pumpPhone(
      tester,
      PersonalInfoPage(
        controller: profile('g21_load_b'),
        securityController: security,
      ),
    );
    expect(security.loading, isTrue);
    expect(find.text(L10n.current.serverPhoneUnavailable), findsNothing);
    expect(find.text(L10n.current.serverEmailStatusUnavailable), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    answer.complete(http.Response(rider, 200));
    await tester.pumpAndSettle();
    expect(find.text('+21620123456'), findsOneWidget);
    expect(find.text(L10n.current.serverPhoneUnavailable), findsNothing);
  });
}
