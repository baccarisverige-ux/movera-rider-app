import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/rider_name.dart';
import 'package:pinput/pinput.dart';

/// rider-r3-10: Back while Verify was in flight closed the code screen;
/// the verify still signed the rider in, but nothing was left mounted to
/// open the app or the new-rider name step, so a signed-in rider sat on
/// the Sign in form.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const env = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );
  const latency = Duration(seconds: 2);

  late MemoryTokenStore tokens;
  late AuthController auth;

  Future<void> openVerifyAndSubmit(WidgetTester tester) async {
    tokens = MemoryTokenStore();
    auth = AuthController(
      auth: AuthRepository(
        api: ApiClient(
          env: env,
          client: InProcessMockClient(latency: latency),
          tokens: tokens,
        ),
        tokens: tokens,
      ),
    );
    final challenge = (await tester.runAsync(
      () => auth.requestOtp(phone: '+46701234567'),
    ))!;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PhoneVerification(
                      challenge: challenge,
                      controller: auth,
                    ),
                  ),
                ),
                child: const Text('Sign in form'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sign in form'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(
      find.descendant(
        of: find.byType(Pinput),
        matching: find.byType(EditableText),
      ),
      '1234',
    );
    await tester.pump();
    await tester.ensureVisible(find.bySemanticsLabel('Verify'));
    await tester.tap(find.bySemanticsLabel('Verify'));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The verify's sign-in steps (session wipe check, push) mix fake and
  /// real async work: let both run until the next screen is up.
  Future<void> settleVerify(WidgetTester tester) async {
    await tester.pump(latency * 2);
    for (var i = 0; i < 60; i++) {
      if (find.byType(RiderNameScreen).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('the back chevron waits while Verify is in flight', (
    tester,
  ) async {
    await openVerifyAndSubmit(tester);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhoneVerification), findsOneWidget);

    await settleVerify(tester);
    expect(find.byType(RiderNameScreen), findsOneWidget);
    expect(find.text('Sign in form'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('system back waits while Verify is in flight', (tester) async {
    await openVerifyAndSubmit(tester);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhoneVerification), findsOneWidget);

    await settleVerify(tester);
    expect(find.byType(RiderNameScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
