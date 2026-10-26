import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/auth/application/auth_error_message.dart';
import 'package:movera_rider/features/auth/presentation/auth_navigation.dart';

/// The old sign-in said "That verification code is not valid" for every
/// failure, including no connection. Each cause now has its own message.
void main() {
  ApiError api(String code, {int? status, Duration? retryAfter}) => ApiError(
    code: code,
    message: 'x',
    statusCode: status,
    retryAfter: retryAfter,
  );

  group('authErrorMessage', () {
    test('no connection is never blamed on the code', () {
      for (final error in <Object>[
        http.ClientException('Failed host lookup'),
        TimeoutException('slow'),
        api('TIMEOUT'),
        api('NETWORK'),
      ]) {
        expect(
          authErrorMessage(error, AuthAction.verifyCode),
          'No connection. Check your internet and try again.',
          reason: '$error',
        );
      }
    });

    test('a wrong code and an expired code are told apart', () {
      expect(
        authErrorMessage(
          api('INVALID_OTP', status: 401),
          AuthAction.verifyCode,
        ),
        "That code isn't right. Check it and try again.",
      );
      for (final code in ['OTP_EXPIRED', 'INVALID_OTP_SESSION']) {
        expect(
          authErrorMessage(api(code, status: 410), AuthAction.verifyCode),
          'This code has expired. Tap Resend code for a new one.',
        );
      }
    });

    test('rate limits say how long to wait', () {
      expect(
        authErrorMessage(
          api(
            'RATE_LIMITED',
            status: 429,
            retryAfter: const Duration(seconds: 45),
          ),
          AuthAction.sendCode,
        ),
        'Too many tries. Try again in 45 seconds.',
      );
      expect(
        authErrorMessage(
          api('X', status: 429, retryAfter: const Duration(seconds: 1)),
          AuthAction.sendCode,
        ),
        'Too many tries. Try again in 1 second.',
      );
      expect(
        authErrorMessage(api('X', status: 429), AuthAction.sendCode),
        'Too many tries. Wait a moment and try again.',
      );
    });

    test('server trouble is not blamed on the rider', () {
      expect(
        authErrorMessage(
          api('SERVER_ERROR', status: 503),
          AuthAction.verifyCode,
        ),
        'Movera is having trouble right now. Try again in a moment.',
      );
    });

    test('anything else falls back to the step the rider was on', () {
      final other = StateError('odd');
      expect(
        authErrorMessage(other, AuthAction.sendCode),
        "Couldn't send the code. Try again.",
      );
      expect(
        authErrorMessage(other, AuthAction.verifyCode),
        "Couldn't check the code. Try again.",
      );
      expect(
        authErrorMessage(other, AuthAction.providerSignIn, provider: 'Google'),
        "Couldn't sign in with Google. Try again.",
      );
    });
  });

  group('swedishNumberFromField', () {
    test('accepts national digits with or without the leading 0', () {
      expect(swedishNumberFromField('70 123 45 67'), '+46701234567');
      expect(swedishNumberFromField('070 123 45 67'), '+46701234567');
      expect(swedishNumberFromField('0701234567'), '+46701234567');
    });

    test('never builds the old invalid +460... number', () {
      expect(swedishNumberFromField('0701234567'), isNot(startsWith('+460')));
    });

    test('rejects empty and too-short input', () {
      expect(swedishNumberFromField(''), isNull);
      expect(swedishNumberFromField('   '), isNull);
      expect(swedishNumberFromField('12345'), isNull);
    });
  });
}
