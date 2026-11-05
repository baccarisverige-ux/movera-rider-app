import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_scene.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Owner 2026-11-02 (same as the driver app, PR #443): the sign-in picture
/// and "Need help?" are fully visible. Job A12 (owner 2026-11-05): the
/// test-numbers button and list are removed in every build.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  AuthController controller() {
    final tokens = MemoryTokenStore();
    final client = MockClient((request) async {
      return http.Response('{"code":"not_found","message":"x"}', 404);
    });
    final api = ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.test.movera.invalid',
      ),
      client: client,
      tokens: tokens,
    );
    return AuthController(
      auth: AuthRepository(api: api, tokens: tokens),
    );
  }

  Future<void> pumpSignIn(WidgetTester tester, Size phone) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SignIn(controller: controller()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
  }

  for (final phone in const [Size(390, 844), Size(375, 812)]) {
    testWidgets(
      '$phone: the picture is tall enough to show the whole skyline',
      (tester) async {
        await pumpSignIn(tester, phone);
        final size = tester.getSize(find.byType(AuthScene));
        expect(AuthScene.showsSkyline(size), isTrue, reason: 'scene $size');
      },
    );

    testWidgets(
      '$phone: "Need help?" is fully on screen under Apple and Google',
      (tester) async {
        await pumpSignIn(tester, phone);
        final link = find.byKey(const ValueKey('auth-need-help'));
        expect(link, findsOneWidget);
        final screen = tester.view.physicalSize.height;
        expect(tester.getBottomLeft(link).dy, lessThanOrEqualTo(screen));
        expect(
          tester.getTopLeft(link).dy,
          greaterThan(tester.getBottomLeft(find.text('Google')).dy),
        );
      },
    );
  }
}
