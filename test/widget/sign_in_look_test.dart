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
/// and "Need help?" are fully visible; the test numbers sit behind one
/// "Test numbers" button, closed until tapped.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  AuthController controller() {
    final tokens = MemoryTokenStore();
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/test-accounts') {
        return http.Response(
          '{"accounts":['
          '{"phone":"+46700000001","app":"rider","status":"test"},'
          '{"phone":"+46700000002","app":"rider","status":"active",'
          '"name":"Test"},'
          '{"phone":"+46700000003","app":"rider","status":"test"},'
          '{"phone":"+46700000004","app":"rider","status":"test"},'
          '{"phone":"+46700000005","app":"rider","status":"active"}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
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

  Future<void> pumpTestBuild(WidgetTester tester, Size phone) async {
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
          home: SignIn(controller: controller(), showTestAccounts: true),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
  }

  for (final phone in const [Size(390, 844), Size(375, 812)]) {
    testWidgets(
      '$phone: test build: the list is closed; "Test numbers" opens it all',
      (tester) async {
        await pumpTestBuild(tester, phone);
        expect(find.byKey(const ValueKey('auth-test-accounts')), findsNothing);
        final button = find.byKey(const ValueKey('auth-test-numbers-button'));
        expect(button, findsOneWidget);
        expect(find.text(L10n.current.testNumbersButton), findsOneWidget);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('auth-test-accounts')),
          findsOneWidget,
        );
        for (var i = 1; i <= 5; i++) {
          expect(
            find.byKey(ValueKey('auth-test-+4670000000$i')),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      '$phone: the picture is tall enough to show the whole skyline',
      (tester) async {
        await pumpTestBuild(tester, phone);
        final size = tester.getSize(find.byType(AuthScene));
        expect(AuthScene.showsSkyline(size), isTrue, reason: 'scene $size');
      },
    );

    testWidgets(
      '$phone: "Need help?" is fully on screen under Apple and Google',
      (tester) async {
        await pumpTestBuild(tester, phone);
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
