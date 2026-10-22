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
import 'package:pinput/pinput.dart';

/// rider-u73: the OTP expiry was checked against the device clock, so a
/// phone whose clock runs ahead of the server by more than the code's
/// lifetime saw every code as expired and never sent it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const env = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );

  late MemoryTokenStore tokens;
  late AuthRepository repository;

  setUp(() {
    tokens = MemoryTokenStore();
    repository = AuthRepository(
      api: ApiClient(env: env, client: InProcessMockClient(), tokens: tokens),
      tokens: tokens,
    );
  });

  /// The challenge a device whose clock is six minutes fast holds: the
  /// server's five-minute expiry is already in the device's past.
  Future<OtpChallenge> fastClockChallenge() async {
    final real = await repository.requestOtp(phone: '+46701234567');
    return OtpChallenge(
      phone: real.phone,
      requestId: real.requestId,
      sessionId: real.sessionId,
      expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      retryAfter: real.retryAfter,
    );
  }

  test(
    'the server, not the device clock, decides that a code expired',
    () async {
      final challenge = await fastClockChallenge();

      await repository.verifyOtp(challenge: challenge, code: '1234');

      expect(await repository.hasSession(), isTrue);
    },
  );

  testWidgets('Verify sends the code even when the device clock is ahead', (
    tester,
  ) async {
    final challenge = await tester.runAsync(fastClockChallenge);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: PhoneVerification(
            challenge: challenge,
            controller: AuthController(auth: repository),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

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

    expect(find.textContaining('This code has expired'), findsNothing);
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && await tokens.readAccess() == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect(await tester.runAsync(tokens.readAccess), isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}
