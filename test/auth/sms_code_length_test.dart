import 'dart:convert';

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
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:pinput/pinput.dart';

/// Contract v0.18.135 `smsSignIn.codeLength` (owner 2026-11-19 "6 digits
/// (Rec.)"): a code sent by SMS is 6 digits, the test code of a test number
/// stays 4. The server says which in the code request's answer
/// (`OtpChallenge.codeLength`, missing = 4), so the same app build works
/// with the test server (4) and a server that sends SMS (6).
class _Server {
  _Server({this.codeLength, this.resendCodeLength});

  /// What the first code request answers as `codeLength` (null: no field,
  /// as a server before v0.18.135).
  final Object? codeLength;

  /// What a resend answers (null: the same as the first).
  final Object? resendCodeLength;
  final List<Map<String, dynamic>> verified = [];
  int codesSent = 0;

  http.Client get client => MockClient((request) async {
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    http.Response json(int status, Map<String, Object?> map) => http.Response(
      jsonEncode(map),
      status,
      headers: {'content-type': 'application/json'},
    );
    if (request.url.path.endsWith('/auth/otp/request')) {
      codesSent++;
      final length = codesSent > 1 && resendCodeLength != null
          ? resendCodeLength
          : codeLength;
      return json(200, {
        'requestId': 'req-$codesSent',
        'sessionId': 'otp-$codesSent',
        'expiresAt': '2030-01-01T10:00:00Z',
        'retryAfterSeconds': 0,
        if (length != null) 'codeLength': length,
      });
    }
    if (request.url.path.endsWith('/auth/otp/verify')) {
      verified.add(body);
      return json(400, {
        'code': 'invalid_request',
        'message': 'Wrong code',
        'reason': 'invalid_otp_code',
      });
    }
    return json(404, {'code': 'not_found', 'message': 'x'});
  });
}

const _env = AppEnv(
  flavor: AppFlavor.test,
  apiBaseUrl: 'https://api.test.movera.invalid',
);

AuthController _auth(_Server server) {
  final tokens = MemoryTokenStore();
  return AuthController(
    auth: AuthRepository(
      api: ApiClient(env: _env, client: server.client, tokens: tokens),
      tokens: tokens,
    ),
  );
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Server> _pumpCodeScreen(
  WidgetTester tester, {
  Object? codeLength,
  Object? resendCodeLength,
  Size screen = const Size(390, 844),
}) async {
  final server = _Server(
    codeLength: codeLength,
    resendCodeLength: resendCodeLength,
  );
  final auth = _auth(server);
  final challenge = (await tester.runAsync(
    () => auth.requestOtp(phone: '+46701234567'),
  ))!;
  tester.view.physicalSize = screen;
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
  return server;
}

Pinput _pinput(WidgetTester tester) =>
    tester.widget<Pinput>(find.byKey(const ValueKey('auth-code')));

Finder _codeField() => find.descendant(
  of: find.byType(Pinput),
  matching: find.byType(EditableText),
);

bool _verifyEnabled(WidgetTester tester) =>
    tester
        .widget<AuthPrimaryButton>(find.byKey(const ValueKey('auth-verify')))
        .onPressed !=
    null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => PhoneVerification.debugWeb = null);

  test(
    'the code request answer says how many digits: 6 for an SMS code, '
    '4 for a test number, and 4 when the field is missing or not 4 / 6',
    () async {
      Future<OtpChallenge> ask(Object? value) =>
          _auth(_Server(codeLength: value)).requestOtp(phone: '+46701234567');
      expect((await ask(6)).codeLength, 6);
      expect((await ask(4)).codeLength, 4);
      // A server before v0.18.135 (the test server today) sends no field.
      expect((await ask(null)).codeLength, 4);
      for (final odd in <Object>[5, 8, 0, -6, 60, '6', 6.5, true]) {
        expect((await ask(odd)).codeLength, 4, reason: '$odd');
      }
    },
  );

  test('a code is complete only with exactly the challenge\'s digits; the '
      'repository refuses another length before any call', () async {
    OtpChallenge challenge(int length) => OtpChallenge(
      phone: '+46701234567',
      requestId: 'req-1',
      sessionId: 'otp-1',
      expiresAt: DateTime.utc(2030),
      retryAfter: Duration.zero,
      codeLength: length,
    );
    expect(challenge(6).isCompleteCode('123456'), isTrue);
    expect(challenge(6).isCompleteCode('1234'), isFalse);
    expect(challenge(6).isCompleteCode('1234567'), isFalse);
    expect(challenge(6).isCompleteCode('12345a'), isFalse);
    expect(challenge(4).isCompleteCode('1234'), isTrue);
    expect(challenge(4).isCompleteCode('123456'), isFalse);
    // The default is the test code's 4 digits.
    expect(
      OtpChallenge(
        phone: '+46701234567',
        requestId: 'req-1',
        sessionId: 'otp-1',
        expiresAt: DateTime.utc(2030),
        retryAfter: Duration.zero,
      ).codeLength,
      4,
    );
    final server = _Server(codeLength: 6);
    final auth = _auth(server);
    final asked = await auth.requestOtp(phone: '+46701234567');
    await expectLater(
      auth.verifyOtp(challenge: asked, code: '1234'),
      throwsArgumentError,
    );
    expect(server.verified, isEmpty);
  });

  testWidgets('an SMS code (codeLength 6): six boxes; four digits send '
      'nothing and leave Verify off; the sixth digit sends the code', (
    tester,
  ) async {
    PhoneVerification.debugWeb = false;
    final server = await _pumpCodeScreen(tester, codeLength: 6);
    expect(_pinput(tester).length, 6);
    // One-time-code autofill (iOS, Android autofill, the web) is kept.
    expect(_pinput(tester).autofillHints, contains(AutofillHints.oneTimeCode));

    await tester.enterText(_codeField(), '1234');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    expect(server.verified, isEmpty);
    expect(_verifyEnabled(tester), isFalse);

    await tester.enterText(_codeField(), '123456');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _settle(tester);
    expect(server.verified, hasLength(1));
    expect(server.verified.single['code'], '123456');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a test number or an older server (no codeLength): four '
      'boxes of the same size as before and the fourth digit sends the code', (
    tester,
  ) async {
    PhoneVerification.debugWeb = false;
    final server = await _pumpCodeScreen(tester);
    expect(_pinput(tester).length, 4);
    expect(_pinput(tester).defaultPinTheme?.width, 68);
    await tester.enterText(_codeField(), '1234');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _settle(tester);
    expect(server.verified.single['code'], '1234');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('six boxes fit a small phone (320 wide) and a normal one '
      'without overflow', (tester) async {
    PhoneVerification.debugWeb = false;
    for (final screen in const [Size(320, 568), Size(390, 844)]) {
      await _pumpCodeScreen(tester, codeLength: 6, screen: screen);
      expect(tester.takeException(), isNull, reason: '$screen');
      final field = tester.getRect(find.byKey(const ValueKey('auth-code')));
      expect(field.left, greaterThanOrEqualTo(0), reason: '$screen');
      expect(field.right, lessThanOrEqualTo(screen.width), reason: '$screen');
      expect(_pinput(tester).defaultPinTheme!.width, lessThan(68));
      expect(_pinput(tester).defaultPinTheme!.width, greaterThanOrEqualTo(36));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a new code with another length changes the boxes (resend)', (
    tester,
  ) async {
    PhoneVerification.debugWeb = false;
    await _pumpCodeScreen(tester, codeLength: 4, resendCodeLength: 6);
    expect(_pinput(tester).length, 4);
    await tester.ensureVisible(find.byKey(const ValueKey('auth-resend')));
    await tester.tap(find.byKey(const ValueKey('auth-resend')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await _settle(tester);
    expect(_pinput(tester).length, 6);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
