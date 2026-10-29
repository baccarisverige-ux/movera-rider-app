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
import 'package:pinput/pinput.dart';

/// Owner, live test 2026-10-26: on the web (iPhone Safari) the first tap on
/// the code boxes did nothing; only a tap elsewhere and a second tap opened
/// the keyboard. The field focused itself when the screen opened, which a
/// browser does without a keyboard, so the first tap met a field that was
/// already focused. In a browser it now waits for the tap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => PhoneVerification.debugWeb = null);

  Future<void> pumpVerify(WidgetTester tester) async {
    final tokens = MemoryTokenStore();
    final auth = AuthController(
      auth: AuthRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.test,
            apiBaseUrl: 'https://api.test.movera.invalid',
          ),
          client: InProcessMockClient(),
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
          home: PhoneVerification(challenge: challenge, controller: auth),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  bool codeFocused(WidgetTester tester) =>
      tester.widget<Pinput>(find.byType(Pinput)).focusNode!.hasFocus;

  testWidgets('in a browser the code field is not focused until the rider '
      'taps it, and one tap focuses it', (tester) async {
    PhoneVerification.debugWeb = true;
    await pumpVerify(tester);
    expect(tester.widget<Pinput>(find.byType(Pinput)).autofocus, isFalse);
    expect(codeFocused(tester), isFalse);
    await tester.tap(find.byType(Pinput));
    await tester.pump(const Duration(milliseconds: 100));
    expect(codeFocused(tester), isTrue);
  });

  testWidgets('the installed app still opens the keyboard at once', (
    tester,
  ) async {
    PhoneVerification.debugWeb = false;
    await pumpVerify(tester);
    expect(tester.widget<Pinput>(find.byType(Pinput)).autofocus, isTrue);
    expect(codeFocused(tester), isTrue);
  });
}
