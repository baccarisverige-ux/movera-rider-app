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
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:pinput/pinput.dart';

/// Verification used to announce a code sent to +96441938184 — a number nobody
/// typed, on one of the first screens a rider ever sees.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const env = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: child),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// The resend countdown is a periodic timer; unmount before the test ends.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  AuthController controller() {
    final tokens = MemoryTokenStore();
    return AuthController(
      auth: AuthRepository(
        api: ApiClient(env: env, client: InProcessMockClient(), tokens: tokens),
        tokens: tokens,
      ),
    );
  }

  testWidgets('rider-r4-11: the resend window runs on the wall clock, so a '
      'suspended app comes back to Resend', (tester) async {
    final auth = controller();
    final challenge = await auth.requestOtp(phone: '+46701234567');
    var now = DateTime(2026, 10, 21, 9);
    await pump(
      tester,
      PhoneVerification(
        challenge: challenge,
        controller: auth,
        clock: () => now,
      ),
    );
    // Two minutes in the background: the timer fires once, not 120 times.
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.widgetWithText(TextButton, 'Resend code'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'resend waits for the server retry window, then sends a new code',
    (tester) async {
      final auth = controller();
      final challenge = await auth.requestOtp(phone: '+46701234567');
      expect(challenge.retryAfter, const Duration(seconds: 30));
      await pump(
        tester,
        PhoneVerification(challenge: challenge, controller: auth),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Resend code in', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('0:30', findRichText: true), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Resend code'), findsNothing);

      await tester.pump(const Duration(seconds: 10));
      expect(find.textContaining('0:20', findRichText: true), findsOneWidget);

      await tester.pump(const Duration(seconds: 21));
      final resend = find.widgetWithText(TextButton, 'Resend code');
      expect(resend, findsOneWidget);

      await tester.ensureVisible(resend);
      await tester.tap(resend);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('New code sent.'), findsOneWidget);
      expect(
        find.textContaining('Resend code in', findRichText: true),
        findsOneWidget,
      );
      await unmount(tester);
    },
  );

  testWidgets('a known number is shown back to the rider, formatted', (
    tester,
  ) async {
    await pump(tester, const PhoneVerification(phoneNumber: '+46701234567'));

    expect(
      find.textContaining('+46 70 123 45 67', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('an unknown number is not invented', (tester) async {
    await pump(tester, const PhoneVerification());

    expect(
      find.textContaining(
        "We've sent a code to your phone",
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('+', findRichText: true), findsNothing);
  });

  testWidgets('Verify stays locked until four digits are entered', (
    tester,
  ) async {
    final auth = controller();
    final challenge = await auth.requestOtp(phone: '+46701234567');
    await pump(
      tester,
      PhoneVerification(challenge: challenge, controller: auth),
    );

    bool verifyEnabled() =>
        tester
            .widget<InkWell>(
              find.descendant(
                of: find.widgetWithText(AuthPrimaryButton, 'Verify'),
                matching: find.byType(InkWell),
              ),
            )
            .onTap !=
        null;

    expect(verifyEnabled(), isFalse);
    final input = find.descendant(
      of: find.byType(Pinput),
      matching: find.byType(EditableText),
    );
    await tester.enterText(input, '123');
    await tester.pump();
    expect(verifyEnabled(), isFalse);
    await tester.enterText(input, '1234');
    await tester.pump();
    expect(verifyEnabled(), isTrue);
    await unmount(tester);
  });

  testWidgets('an expired code says so instead of calling it wrong', (
    tester,
  ) async {
    final auth = controller();
    final expired = OtpChallenge(
      phone: '+46701234567',
      requestId: 'req_expired',
      sessionId: 'otp_expired',
      expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      retryAfter: Duration.zero,
    );
    await pump(tester, PhoneVerification(challenge: expired, controller: auth));

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
    await tester.pump();

    expect(find.textContaining('This code has expired'), findsOneWidget);
    expect(find.textContaining("isn't right"), findsNothing);
    await unmount(tester);
  });
}
