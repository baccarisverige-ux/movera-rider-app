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
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.149 `adminSessions.apps` (owner Rules decisions/driver-g12.md
/// Q6): an admin signed this phone out. The next call is 401 reason
/// `signed_out_by_movera`, so is the refresh; the app signs out through the
/// one existing path (tokens cleared, onSessionExpired) and Sign in shows
/// "You were signed out by Movera" once. A normal 401 / expired session
/// does not show it.

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

Widget _app(Widget home) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, __) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// A call answered 401 ([callReason]) whose refresh answers 401
/// ([refreshReason]); counts the app's session-expired calls.
Future<({int expired, MemoryTokenStore tokens})> _refused({
  String? callReason,
  String? refreshReason,
}) async {
  final tokens = MemoryTokenStore();
  await tokens.save(access: 'old-access', refresh: 'old-refresh');
  var expired = 0;
  final api = ApiClient(
    env: _env,
    tokens: tokens,
    onSessionExpired: () async => expired++,
    client: MockClient((request) async {
      if (request.url.path == '/api/v1/auth/refresh') {
        return _json(401, {
          'code': 'unauthenticated',
          'message': 'Please sign in again.',
          'reason': ?refreshReason,
        });
      }
      return _json(401, {
        'code': 'unauthenticated',
        'message': 'Please sign in again.',
        'reason': ?callReason,
      });
    }),
  );
  await expectLater(api.get('/api/v1/rider/profile'), throwsA(isA<ApiError>()));
  return (expired: expired, tokens: tokens);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    SignedOutNotice.clear();
    L10n.use('en');
  });

  test('a call and refresh refused signed_out_by_movera sign out once and '
      'say "by Movera"', () async {
    final result = await _refused(
      callReason: 'signed_out_by_movera',
      refreshReason: 'signed_out_by_movera',
    );
    expect(result.expired, 1);
    expect(await result.tokens.readAccess(), isNull);
    final notice = SignedOutNotice.current.value!;
    expect(notice, const SignedOut(SignedOutKind.revoked, byMovera: true));
    expect(notice.text, L10n.current.signedOutRevoked);
    expect(notice.detail, 'You were signed out by Movera');
    final reasons = (_contract['auth'] as Map)['signedOut']['reasons'] as Map;
    expect(reasons['signed_out_by_movera'], 'revoked');
    expect(SignedOutNotice.reasons['signed_out_by_movera']?.name, 'revoked');
  });

  test('a normal 401 or an expired session never says "by Movera"', () async {
    for (final reason in [null, 'session_expired', 'session_ended']) {
      SignedOutNotice.clear();
      final result = await _refused(refreshReason: reason);
      expect(result.expired, 1, reason: '$reason');
      final notice = SignedOutNotice.current.value;
      expect(notice?.byMovera, isFalse, reason: '$reason');
      expect(notice?.detail, isNot(L10n.current.signedOutByMovera));
    }
  });

  test('the words are the contract\'s byMoveraTexts in sv / fr / en', () {
    final texts =
        (_contract['auth'] as Map)['signedOut']['byMoveraTexts'] as Map;
    for (final lang in ['sv', 'fr', 'en']) {
      L10n.use(lang);
      expect(L10n.current.signedOutByMovera, texts[lang], reason: lang);
    }
  });

  testWidgets('Sign in shows it with the revoked title; own Sign out clears '
      'it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SignedOutNotice.current.value = SignedOutNotice.forReason(
      'signed_out_by_movera',
    );
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
    await tester.pumpWidget(_app(SignIn(controller: auth)));
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('auth-signed-out')), findsOneWidget);
    expect(find.text(L10n.current.signedOutRevoked), findsOneWidget);
    expect(find.text('You were signed out by Movera'), findsOneWidget);
    expect(find.text(L10n.current.signedOutDetailRevoked), findsNothing);
    unawaited(auth.signOut().catchError((_) {}));
    await tester.pump();
    expect(find.text('You were signed out by Movera'), findsNothing);
  });
}
