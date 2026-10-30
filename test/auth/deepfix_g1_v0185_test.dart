import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/signed_out_notice.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/data/provider_token_source.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/presentation/phone_verify.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/auth/presentation/widgets/auth_controls.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.5 §30, owner decisions G1-B1, B3, B5, B6, D3 (deep second
/// audit of driver group 1, applied to the rider app).

const _env = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.test.movera.invalid',
);

http.Response _json(int status, Map<String, Object?> map) => http.Response(
  jsonEncode(map),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> get _contract =>
    jsonDecode(File('contracts/contract.json').readAsStringSync())
        as Map<String, dynamic>;

class _Token implements ProviderTokenSource {
  @override
  Future<ProviderIdentityToken?> obtain(String provider) async =>
      ProviderIdentityToken(provider: provider, idToken: 'id-$provider');
}

Widget _app(Widget home) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, __) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    SignedOutNotice.clear();
    L10n.use('en');
  });

  group('G1-D3 signed-out message (auth.signedOut)', () {
    Future<ApiClient> expireWith(String? reason) async {
      final tokens = MemoryTokenStore();
      await tokens.save(access: 'old-access', refresh: 'old-refresh');
      return ApiClient(
        env: _env,
        tokens: tokens,
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/refresh') {
            return _json(401, {
              'code': 'unauthenticated',
              'message': 'Please sign in again.',
              'reason': ?reason,
            });
          }
          return _json(401, {'code': 'unauthenticated', 'message': 'x'});
        }),
      );
    }

    test('every contract reason maps to its kind', () {
      final reasons = (_contract['auth'] as Map)['signedOut']['reasons'] as Map;
      expect(reasons, isNotEmpty);
      for (final entry in reasons.entries) {
        expect(
          SignedOutNotice.reasons[entry.key]?.name,
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('the texts are the contract texts in sv / fr / en', () {
      final c = (_contract['auth'] as Map)['signedOut'] as Map;
      for (final lang in ['sv', 'fr', 'en']) {
        L10n.use(lang);
        expect(L10n.current.signedOutExpired, c['texts']['expired'][lang]);
        expect(L10n.current.signedOutRevoked, c['texts']['revoked'][lang]);
        expect(
          L10n.current.signedOutDetailExpired,
          c['detail']['expired'][lang],
        );
        expect(
          L10n.current.signedOutDetailRevoked,
          c['detail']['revoked'][lang],
        );
      }
    });

    test('a refresh refused with session_expired says "30 days"', () async {
      final api = await expireWith('session_expired');
      await expectLater(
        api.get('/api/v1/rider/profile'),
        throwsA(isA<ApiError>()),
      );
      expect(
        SignedOutNotice.current.value,
        const SignedOut(SignedOutKind.expired),
      );
      expect(
        SignedOutNotice.current.value!.detail,
        L10n.current.signedOutDetailExpired,
      );
    });

    test('refresh_token_reused says "Movera ended your session"', () async {
      final api = await expireWith('refresh_token_reused');
      await expectLater(
        api.get('/api/v1/rider/profile'),
        throwsA(isA<ApiError>()),
      );
      expect(
        SignedOutNotice.current.value,
        const SignedOut(SignedOutKind.revoked),
      );
    });

    testWidgets('the sign-in screen shows the message and the reason', (
      tester,
    ) async {
      _phone(tester);
      SignedOutNotice.current.value = const SignedOut(SignedOutKind.revoked);
      await tester.pumpWidget(
        _app(
          SignIn(
            controller: AuthController(
              auth: AuthRepository(
                api: ApiClient(
                  env: _env,
                  client: MockClient((_) async => _json(404, {})),
                  tokens: MemoryTokenStore(),
                ),
                tokens: MemoryTokenStore(),
              ),
            ),
            showTestAccounts: false,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(find.text(L10n.current.signedOutRevoked), findsOneWidget);
      expect(find.text(L10n.current.signedOutDetailRevoked), findsOneWidget);
    });

    test('no message after the rider\'s own Sign out', () async {
      SignedOutNotice.current.value = const SignedOut(SignedOutKind.expired);
      final tokens = MemoryTokenStore();
      final auth = AuthController(
        auth: AuthRepository(
          api: ApiClient(
            env: _env,
            client: MockClient((_) async => _json(204, {})),
            tokens: tokens,
          ),
          tokens: tokens,
        ),
      );
      // Cleared before anything else of the sign-out runs (the rest needs
      // the app's scope and is covered by the sign-out tests).
      unawaited(auth.signOut().catchError((_) {}));
      expect(SignedOutNotice.current.value, isNull);
    });
  });

  group('G1-B6 refresh retry (auth.tokens.refreshRetry)', () {
    test(
      'a lost refresh answer is asked again at once with the same token',
      () async {
        final tokens = MemoryTokenStore();
        await tokens.save(access: 'old-access', refresh: 'r1');
        final sent = <String>[];
        final api = ApiClient(
          env: _env,
          tokens: tokens,
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/auth/refresh') {
              sent.add(
                (jsonDecode(request.body) as Map)['refreshToken'] as String,
              );
              if (sent.length == 1)
                throw http.ClientException('connection lost');
              return _json(200, {
                'accessToken': 'new-access',
                'refreshToken': 'r2',
              });
            }
            final auth = request.headers['Authorization'];
            return auth == 'Bearer new-access'
                ? _json(200, {'ok': true})
                : _json(401, {'code': 'unauthenticated', 'message': 'x'});
          }),
        );
        expect(
          await api.get('/api/v1/rider/profile'),
          containsPair('ok', true),
        );
        expect(sent, ['r1', 'r1']);
        expect(await tokens.readRefresh(), 'r2');
        expect(SignedOutNotice.current.value, isNull);
      },
    );

    test('the window is the contract\'s 60 s; one retry', () {
      expect(
        (_contract['auth'] as Map)['tokens']['refreshRetryWindowSeconds'],
        60,
      );
      expect(ApiClient.refreshAttempts, 2);
    });
  });

  group('G1-B1 Apple / Google', () {
    test('sends { provider, idToken, app: rider }', () async {
      late Map<String, dynamic> body;
      final tokens = MemoryTokenStore();
      final auth = AuthController(
        providerTokens: _Token(),
        auth: AuthRepository(
          tokens: tokens,
          api: ApiClient(
            env: _env,
            tokens: tokens,
            client: MockClient((request) async {
              body = jsonDecode(request.body) as Map<String, dynamic>;
              return _json(200, {'code': 'PHONE_REQUIRED', 'linkToken': 'l1'});
            }),
          ),
        ),
      );
      final result = await auth.signIn(provider: 'google');
      expect(body, {
        'provider': 'google',
        'idToken': 'id-google',
        'app': 'rider',
      });
      expect(result, isA<ProviderPhoneRequired>());
    });

    test('provider_not_configured and no SDK both say "coming soon"', () async {
      const notConfigured = ApiError(
        code: 'unavailable',
        reason: 'provider_not_configured',
        message: 'x',
        statusCode: 503,
      );
      expect(
        authErrorMessage(
          notConfigured,
          AuthAction.providerSignIn,
          provider: 'Apple',
        ),
        L10n.current.providerComingSoon,
      );
      final requests = <http.Request>[];
      final tokens = MemoryTokenStore();
      final auth = AuthController(
        auth: AuthRepository(
          tokens: tokens,
          api: ApiClient(
            env: _env,
            tokens: tokens,
            client: MockClient((r) async {
              requests.add(r);
              return _json(400, {});
            }),
          ),
        ),
      );
      Object? error;
      try {
        await auth.signIn(provider: 'apple');
      } catch (e) {
        error = e;
      }
      expect(error, isA<ProviderUnavailable>());
      expect(requests, isEmpty, reason: 'never a request without a token');
      expect(
        authErrorMessage(error!, AuthAction.providerSignIn, provider: 'Apple'),
        L10n.current.providerComingSoon,
      );
    });
  });

  group('G1-B3 five wrong codes', () {
    testWidgets('Verify is off and the boxes stay quiet until a new code', (
      tester,
    ) async {
      _phone(tester);
      var verifies = 0;
      final tokens = MemoryTokenStore();
      final auth = AuthController(
        auth: AuthRepository(
          tokens: tokens,
          api: ApiClient(
            env: _env,
            tokens: tokens,
            client: MockClient((request) async {
              if (request.url.path == '/api/v1/auth/otp/verify') {
                verifies++;
                return _json(429, {
                  'code': 'rate_limited',
                  'message': 'x',
                  'reason': 'otp_too_many_attempts',
                });
              }
              return _json(404, {});
            }),
          ),
        ),
      );
      await tester.pumpWidget(
        _app(
          PhoneVerification(
            controller: auth,
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
      await tester.enterText(find.byType(EditableText), '9999');
      await _settle(tester);
      expect(verifies, 1);
      final message = L10n.current.errTooManyWrongCodes(
        L10n.current.resendCode,
      );
      expect(find.text(message), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth-resend-highlight')),
        findsOneWidget,
      );

      // Verify is disabled even with 4 digits typed, and typing does not
      // send nor hide the message.
      await tester.enterText(find.byType(EditableText), '1234');
      await _settle(tester);
      expect(verifies, 1);
      expect(find.text(message), findsOneWidget);
      final verify = tester.widget<AuthPrimaryButton>(
        find.widgetWithText(AuthPrimaryButton, L10n.current.verify),
      );
      expect(verify.onPressed, isNull);
    });
  });

  group('G1-B5 / B6 sign-in words and labels', () {
    testWidgets('consent words, "or", separate links, field labels', (
      tester,
    ) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      String? opened;
      await tester.pumpWidget(
        _app(Scaffold(body: LegalLinksRow(onOpen: (k) => opened = k))),
      );
      expect(
        find.bySemanticsLabel(L10n.current.legalTermsLink),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(L10n.current.legalPrivacyLink),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('auth-legal-privacy')));
      expect(opened, 'privacy');
      handle.dispose();
    });

    test('same words as the driver app, sv / fr / en', () {
      final pairs = {
        'consentPrefix': 'authConsentPrefix',
        'consentTerms': 'authConsentTerms',
        'consentPrivacy': 'authConsentPrivacy',
        'consentLabel': 'authConsentLabel',
        'authOr': 'authOr',
        'providerComingSoon': 'authProviderComingSoon',
      };
      for (final lang in ['sv', 'fr', 'en']) {
        final rider =
            jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
                as Map<String, dynamic>;
        expect(
          rider['consentPrefix'],
          startsWith(switch (lang) {
            'sv' => 'Genom att fortsätta',
            'fr' => 'En continuant',
            _ => 'By continuing',
          }),
        );
        for (final key in pairs.keys) {
          expect(rider[key], isA<String>(), reason: '$lang $key');
        }
      }
      expect(L10n.languages.map((l) => l.name), [
        'Svenska',
        'Français',
        'English',
      ]);
      expect(L10n.languageOf('xx').code, 'en');
    });

    testWidgets('sign-in: a new try clears the last error line', (
      tester,
    ) async {
      _phone(tester);
      final calls = <int>[];
      final tokens = MemoryTokenStore();
      final done = Completer<http.Response>();
      final auth = AuthController(
        auth: AuthRepository(
          tokens: tokens,
          api: ApiClient(
            env: _env,
            tokens: tokens,
            client: MockClient((request) async {
              if (request.url.path != '/api/v1/auth/otp/request') {
                return _json(404, {});
              }
              calls.add(calls.length);
              if (calls.length == 1) {
                throw http.ClientException('offline');
              }
              return done.future;
            }),
          ),
        ),
      );
      await tester.pumpWidget(
        _app(SignIn(controller: auth, showTestAccounts: false)),
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.enterText(find.byType(EditableText).first, '701740605');
      final consent = find.byKey(const ValueKey('auth-consent'));
      await tester.tapAt(tester.getTopLeft(consent) + const Offset(12, 12));
      await tester.pump();
      await tester.tap(find.text(L10n.current.continueLabel));
      await _settle(tester);
      expect(find.text(L10n.current.errOffline), findsOneWidget);
      await tester.tap(find.text(L10n.current.continueLabel));
      await tester.pump();
      expect(find.text(L10n.current.errOffline), findsNothing);
      done.complete(_json(500, {}));
      await _settle(tester);
    });
  });
}
