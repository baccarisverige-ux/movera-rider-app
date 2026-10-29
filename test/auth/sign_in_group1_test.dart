import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/auth/presentation/start_error.dart';
import 'package:movera_rider/features/ride_booking/presentation/ride_restore_gate.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:pinput/pinput.dart';

/// Owner decisions of 2026-10-29, driver app group 1 "Sign in, sign up,
/// language", applied to the rider app too (contract v0.15.0 §24).

http.Response _json(int status, Map<String, Object?> map) => http.Response(
  jsonEncode(map),
  status,
  headers: {'content-type': 'application/json'},
);

class _Server {
  _Server(this.answer);
  final FutureOr<http.Response> Function(http.Request request) answer;
  final List<http.Request> requests = [];
  http.Client get client => MockClient((request) async {
    requests.add(request);
    return answer(request);
  });
}

AuthController _controller(_Server server) {
  final tokens = MemoryTokenStore();
  final api = ApiClient(
    env: const AppEnv(
      flavor: AppFlavor.staging,
      apiBaseUrl: 'https://api.test.movera.invalid',
    ),
    client: server.client,
    tokens: tokens,
  );
  return AuthController(
    auth: AuthRepository(api: api, tokens: tokens),
  );
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget home) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, __) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _continueWith(WidgetTester tester, String typed) async {
  await tester.enterText(find.byType(EditableText).first, typed);
  final consent = find.byKey(const ValueKey('auth-consent'));
  await tester.tapAt(tester.getTopLeft(consent) + const Offset(12, 12));
  await tester.pump();
  await tester.tap(find.text(L10n.current.continueLabel));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<dynamic> waitCases;
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // contracts/fixtures/sign_in.json#waitDisplay, the cases every app shows
    // the same way.
    waitCases =
        (jsonDecode(File('contracts/fixtures/sign_in.json').readAsStringSync())
                as Map<String, dynamic>)['waitDisplay']
            as List<dynamic>;
  });
  tearDown(() {
    PhoneVerification.debugWeb = null;
    RideRestoreGate.debugRoot = null;
  });

  group('decision 4: a wait is shown in minutes', () {
    test('fixtures/sign_in.json#waitDisplay', () {
      for (final raw in waitCases) {
        final c = raw as Map<String, dynamic>;
        final want = c['expect'] as Map<String, dynamic>;
        final value = want['value'] as int;
        expect(
          authWaitText(Duration(seconds: c['retryAfterSeconds'] as int)),
          want['unit'] == 'seconds'
              ? L10n.current.retrySeconds(value)
              : L10n.current.retryMinutes(value),
          reason: '$c',
        );
      }
    });

    test('429 otp_too_many says "Try again in 42 min"', () {
      const error = ApiError(
        code: 'rate_limited',
        reason: 'otp_too_many',
        message: 'x',
        statusCode: 429,
        retryAfter: Duration(seconds: 2501),
      );
      expect(
        authErrorMessage(error, AuthAction.sendCode),
        L10n.current.errTooManyIn('42 min'),
      );
    });

    test('decision 3: 429 otp_too_many_attempts names the resend button', () {
      const error = ApiError(
        code: 'rate_limited',
        reason: 'otp_too_many_attempts',
        message: 'x',
        statusCode: 429,
      );
      expect(
        authErrorMessage(error, AuthAction.verifyCode),
        L10n.current.errTooManyWrongCodes(L10n.current.resendCode),
      );
    });
  });

  group('decision 1: the sign-in calls wait up to 60 s', () {
    testWidgets('no error after 20 s, "Starting the server…" after 5 s', (
      tester,
    ) async {
      _phoneSize(tester);
      final answer = Completer<http.Response>();
      final server = _Server((request) {
        if (request.url.path == '/api/v1/auth/otp/request') {
          return answer.future;
        }
        return _json(404, {'code': 'not_found', 'message': 'x'});
      });
      await tester.pumpWidget(
        _app(SignIn(controller: _controller(server), showTestAccounts: false)),
      );
      await tester.pump(const Duration(seconds: 6));
      await _continueWith(tester, '70 174 06 05');
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('auth-slow-server')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(L10n.current.startingServer), findsOneWidget);
      // The old 30 s limit is passed here too.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(L10n.current.errOffline), findsNothing);
      answer.complete(_json(500, {'code': 'internal', 'message': 'x'}));
      await _settle(tester);
      expect(find.byKey(const ValueKey('auth-slow-server')), findsNothing);
      expect(ApiClient.signInTimeout, const Duration(seconds: 60));
    });
  });

  group('decision 5: the waiting list', () {
    testWidgets('a restricted number gets "Join the waiting list"; it saves '
        'the number', (tester) async {
      _phoneSize(tester);
      final server = _Server((request) {
        switch (request.url.path) {
          case '/api/v1/auth/otp/request':
            return _json(403, {
              'code': 'forbidden',
              'message': 'x',
              'reason': 'sign_in_restricted',
            });
          case '/api/v1/auth/waitlist':
            return _json(200, {'status': 'saved', 'requestId': 'r1'});
        }
        return _json(404, {'code': 'not_found', 'message': 'x'});
      });
      await tester.pumpWidget(
        _app(SignIn(controller: _controller(server), showTestAccounts: false)),
      );
      await tester.pump(const Duration(seconds: 6));
      await _continueWith(tester, '70 555 12 34');
      await _settle(tester);
      expect(find.text(L10n.current.signInRestricted), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-join-waitlist')));
      await _settle(tester);
      final sent = server.requests.last;
      expect(sent.url.path, '/api/v1/auth/waitlist');
      // The number the code was asked for (in the test's default country).
      final asked = jsonDecode(server.requests.first.body) as Map;
      expect(jsonDecode(sent.body), {
        'phone': asked['phone'],
        'app': 'rider',
        'locale': 'en',
      });
      expect(find.text(L10n.current.waitlistSaved), findsOneWidget);
    });
  });

  group('decision 6: test numbers only in test builds', () {
    _Server accounts() => _Server((request) {
      if (request.url.path == '/api/v1/auth/test-accounts') {
        return _json(200, {
          'accounts': [
            {'phone': '+46701740605', 'app': 'rider', 'status': 'test'},
            {
              'phone': '+46701740606',
              'app': 'rider',
              'status': 'active',
              'name': 'Ada',
            },
            {'phone': '+46701740606', 'app': 'driver', 'status': 'pending'},
          ],
        });
      }
      return _json(404, {'code': 'not_found', 'message': 'x'});
    });

    testWidgets('a test build lists the rider numbers; a tap fills the field', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(
        _app(
          SignIn(controller: _controller(accounts()), showTestAccounts: true),
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const ValueKey('auth-test-accounts')), findsOneWidget);
      expect(find.text(L10n.current.testStatusNew), findsOneWidget);
      expect(find.text(L10n.current.testStatusActive), findsOneWidget);
      final row = find.byKey(const ValueKey('auth-test-+46701740606'));
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();
      final typed = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((field) => field.controller.text.replaceAll(' ', ''));
      expect(typed, contains('701740606'));
    });

    testWidgets('a store build never asks', (tester) async {
      _phoneSize(tester);
      final server = accounts();
      await tester.pumpWidget(
        _app(SignIn(controller: _controller(server), showTestAccounts: false)),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(find.byKey(const ValueKey('auth-test-accounts')), findsNothing);
      expect(server.requests, isEmpty);
    });
  });

  group('the code screen', () {
    Future<void> pumpVerify(WidgetTester tester, _Server server) async {
      _phoneSize(tester);
      await tester.pumpWidget(
        _app(
          PhoneVerification(
            controller: _controller(server),
            challenge: OtpChallenge(
              phone: '+46701740605',
              requestId: 'r',
              sessionId: 'otp-1',
              expiresAt: DateTime.utc(2030),
              retryAfter: Duration.zero,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('decision 3: the resend button is highlighted after 5 wrong '
        'codes, until a new code is sent', (tester) async {
      final server = _Server((request) {
        switch (request.url.path) {
          case '/api/v1/auth/otp/verify':
            return _json(429, {
              'code': 'rate_limited',
              'message': 'x',
              'reason': 'otp_too_many_attempts',
            });
          case '/api/v1/auth/otp/request':
            return _json(200, {
              'requestId': 'r2',
              'sessionId': 'otp-2',
              'expiresAt': '2030-01-01T10:00:00Z',
              'retryAfterSeconds': 0,
            });
        }
        return _json(404, {'code': 'not_found', 'message': 'x'});
      });
      await pumpVerify(tester, server);
      await tester.enterText(find.byType(EditableText), '9999');
      await tester.pump();
      await tester.tap(find.text(L10n.current.verify));
      await _settle(tester);
      expect(
        find.text(L10n.current.errTooManyWrongCodes(L10n.current.resendCode)),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('auth-resend-highlight')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('auth-resend-highlight')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('auth-resend-highlight')), findsNothing);
    });

    testWidgets('decision 7: one-time-code autofill', (tester) async {
      await pumpVerify(tester, _Server((_) => _json(404, {})));
      expect(tester.widget<Pinput>(find.byType(Pinput)).autofillHints, const [
        AutofillHints.oneTimeCode,
      ]);
    });

    testWidgets('decision 9: in a browser the field never focuses itself, and '
        'a tap on the focused field reconnects the text input', (tester) async {
      PhoneVerification.debugWeb = true;
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          null,
        ),
      );
      await pumpVerify(tester, _Server((_) => _json(404, {})));
      final pin = find.byType(Pinput);
      expect(tester.widget<Pinput>(pin).autofocus, isFalse);
      expect(tester.widget<Pinput>(pin).focusNode!.hasFocus, isFalse);
      await tester.tap(pin);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<Pinput>(pin).focusNode!.hasFocus, isTrue);
      calls.clear();
      await tester.tap(pin);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, contains('TextInput.clearClient'));
      expect(
        calls.lastIndexOf('TextInput.setClient'),
        greaterThan(calls.indexOf('TextInput.clearClient')),
      );
      expect(tester.widget<Pinput>(pin).focusNode!.hasFocus, isTrue);
    });
  });

  group('decision 2: the start screen', () {
    testWidgets('a spinner only after 2 s', (tester) async {
      final never = Completer<Widget>();
      RideRestoreGate.debugRoot = () => never.future;
      await tester.pumpWidget(_app(const RideRestoreGate()));
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.byKey(const ValueKey('start-spinner')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('start-spinner')), findsOneWidget);
      never.complete(const Text('home'));
      await tester.pump();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a failed start offers Try again, Sign out and Contact '
        'support', (tester) async {
      var attempts = 0;
      RideRestoreGate.debugRoot = () async {
        attempts++;
        if (attempts == 1) throw StateError('store');
        return const Text('home');
      };
      await tester.pumpWidget(_app(const RideRestoreGate()));
      await tester.pump();
      await tester.pump();
      expect(find.byType(StartError), findsOneWidget);
      expect(find.text(L10n.current.tryAgain), findsOneWidget);
      expect(find.text(L10n.current.startSignOut), findsOneWidget);
      expect(find.text(L10n.current.startContactSupport), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start-retry')));
      await tester.pump();
      await tester.pump();
      expect(find.text('home'), findsOneWidget);
    });

    // Owner 2026-10-29 (screen driver-01c): "Open the in-app support chat".
    testWidgets('Contact support opens the in-app support messages', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(StartError(onRetry: () {}, onSignedOut: () {})),
      );
      await tester.tap(find.byKey(const ValueKey('start-support')));
      await _settle(tester);
      expect(find.byType(SupportMessages), findsOneWidget);
    });
  });

  // Owner 2026-10-29: "It's not help page !! It's only written need help ?
  // When clic user can see info"; details come later ("coming soon").
  group('Need help? before sign-in', () {
    testWidgets('a small text that shows a box with the contact details', (
      tester,
    ) async {
      _phoneSize(tester);
      final server = _Server((_) => http.Response('', 204));
      await tester.pumpWidget(
        _app(SignIn(controller: _controller(server), showTestAccounts: false)),
      );
      await tester.pump(const Duration(seconds: 6));
      final link = find.byKey(const ValueKey('auth-need-help'));
      expect(link, findsOneWidget);
      expect(find.text('Need help?'), findsOneWidget);
      await tester.ensureVisible(link);
      await tester.tap(link);
      await _settle(tester);
      expect(find.byKey(const ValueKey('auth-need-help-box')), findsOneWidget);
      expect(find.text('Contact details coming soon'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('auth-need-help-close')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('auth-need-help-box')), findsNothing);
    });
  });
}
