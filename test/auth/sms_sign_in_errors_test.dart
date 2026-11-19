import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.135 `smsSignIn.errors` (owner 2026-11-19 "Yes, build it
/// now (Rec.)"): real sign-in codes by SMS add two answers to the code
/// request. Both are `503 unavailable`; before this the rider read "Movera
/// is having trouble right now", which says nothing about the SMS.
void main() {
  const notSent = ApiError(
    code: 'unavailable',
    reason: 'sms_not_sent',
    message: 'We could not send the SMS. Check the number and try again.',
    statusCode: 503,
    retryAfter: Duration(seconds: 30),
  );
  const dailyLimit = ApiError(
    code: 'unavailable',
    reason: 'sms_daily_limit',
    message: 'We cannot send more SMS codes right now. Try again later.',
    statusCode: 503,
    retryAfter: Duration(hours: 5),
  );

  tearDown(() => L10n.use('en'));

  test('the code request carries the app language, so the SMS is written '
      'in it (contract smsSignIn.language)', () async {
    final bodies = <Map<String, dynamic>>[];
    final tokens = MemoryTokenStore();
    final auth = AuthRepository(
      tokens: tokens,
      api: ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.test.movera.invalid',
        ),
        tokens: tokens,
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'requestId': 'req-1',
              'sessionId': 'otp-1',
              'expiresAt': '2030-01-01T10:00:00Z',
              'retryAfterSeconds': 30,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    for (final lang in const ['sv', 'fr', 'en']) {
      L10n.use(lang);
      await auth.requestOtp(phone: '+46 70 123 45 67');
    }
    expect([for (final body in bodies) body['locale']], ['sv', 'fr', 'en']);
    expect(bodies.first['phone'], '+46701234567');
    expect(bodies.first['app'], 'rider');
  });

  test('sms_not_sent: the SMS could not be sent, in sv / fr / en '
      '(contract smsSignIn.texts.smsNotSent)', () {
    expect(isSmsNotSent(notSent), isTrue);
    expect(isSmsDailyLimit(notSent), isFalse);
    const texts = {
      'en': 'We could not send the SMS. Check the number and try again.',
      'sv': 'Vi kunde inte skicka sms:et. Kontrollera numret och försök igen.',
      'fr':
          'Nous n’avons pas pu envoyer le SMS. Vérifiez le numéro et '
          'réessayez.',
    };
    for (final entry in texts.entries) {
      L10n.use(entry.key);
      for (final action in AuthAction.values) {
        expect(
          authErrorMessage(notSent, action),
          entry.value,
          reason: '${entry.key} $action',
        );
      }
    }
  });

  test('sms_daily_limit: no more SMS codes right now, in sv / fr / en '
      '(contract smsSignIn.texts.smsDailyLimit)', () {
    expect(isSmsDailyLimit(dailyLimit), isTrue);
    const texts = {
      'en': 'We cannot send more SMS codes right now. Try again later.',
      'sv': 'Vi kan inte skicka fler sms-koder just nu. Försök igen senare.',
      'fr':
          'Nous ne pouvons plus envoyer de codes par SMS pour le moment. '
          'Réessayez plus tard.',
    };
    for (final entry in texts.entries) {
      L10n.use(entry.key);
      expect(
        authErrorMessage(dailyLimit, AuthAction.sendCode),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('other 503 answers keep the server-trouble text; the waiting-list '
      'answer is unchanged', () {
    const busy = ApiError(
      code: 'unavailable',
      reason: 'server_busy',
      message: 'x',
      statusCode: 503,
    );
    expect(
      authErrorMessage(busy, AuthAction.sendCode),
      'Movera is having trouble right now. Try again in a moment.',
    );
    const restricted = ApiError(
      code: 'forbidden',
      reason: 'sign_in_restricted',
      message: 'x',
      statusCode: 403,
    );
    expect(isSignInRestricted(restricted), isTrue);
    expect(isSmsNotSent(restricted), isFalse);
  });
}
