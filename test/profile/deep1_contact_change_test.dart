import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';
import 'package:movera_rider/features/profile/presentation/contact_change.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';

/// Decision driver-g1 (riders too): phone / e-mail change through
/// contract v0.18.14 `deepFix1.accountChange`.
void main() {
  Future<List<(String, Map<String, dynamic>)>> open(
    WidgetTester tester,
    ContactKind kind,
    Map<String, dynamic> Function(String path) answer, {
    void Function()? saved,
    Future<Map<String, Object>> Function(String app, String phone)?
    deviceFields,
    PhoneCountry? startCountry,
  }) async {
    final sent = <(String, Map<String, dynamic>)>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ContactChangePage(
          kind: kind,
          post: (path, body) async {
            sent.add((path, body));
            return answer(path);
          },
          onSaved: () async => saved?.call(),
          deviceFields: deviceFields,
          startCountry: () async => startCountry ?? PhoneCountries.sweden,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sent;
  }

  testWidgets('a new number: change, the code, verify, saved', (tester) async {
    var saved = 0;
    final sent = await open(
      tester,
      ContactKind.phone,
      (path) => path.endsWith('/change')
          ? {'sessionId': 'ses_1', 'retryAfterSeconds': 30}
          : {'phone': '+46701740633'},
      saved: () => saved++,
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      '+46701740633',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.single.$1, '/api/v1/account/phone/change');
    expect(find.text('We sent a code to the new number.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('contact-code')), '1234');
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.last.$1, '/api/v1/account/phone/verify');
    expect(sent.last.$2, {
      'phone': '+46701740633',
      'sessionId': 'ses_1',
      'code': '1234',
    });
    expect(saved, 1);
    expect(find.text('Phone number changed'), findsOneWidget);
  });

  testWidgets('an e-mail: change → challenge → verify; a used number says so', (
    tester,
  ) async {
    final sent = await open(
      tester,
      ContactKind.email,
      (path) => path.endsWith('/change')
          // G30 (contract v0.18.76, Rule 35): only 'sent' shows the code
          // field; pending_provider is covered by g30_email_verified_test.
          ? {'challengeId': 'ch_1', 'delivery': 'sent'}
          : {'email': 'ny@example.test'},
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      'ny@example.test',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('contact-code')), '4321');
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.last.$2, {'challengeId': 'ch_1', 'code': '4321'});

    await open(
      tester,
      ContactKind.phone,
      (_) => throw const ApiError(
        code: 'conflict',
        reason: 'phone_taken',
        message: 'x',
        statusCode: 409,
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      '+46700000000',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('This number is already used by another account'),
      findsOneWidget,
    );
  });

  for (final (status, reason, text) in [
    (
      403,
      'reauth_required',
      'Sign in again first, then change your number/e-mail',
    ),
    (429, 'change_too_many', 'Too many changes — try again in an hour'),
    // v0.18.138 deviceCheck.phoneChange: the real-phone check failed.
    (
      403,
      'device_check_failed',
      'This phone could not be checked. Install the app from the official store and try again.',
    ),
  ]) {
    testWidgets('$status $reason has its own message', (tester) async {
      await open(
        tester,
        ContactKind.email,
        (_) => throw ApiError(
          code: 'refused',
          reason: reason,
          message: 'x',
          statusCode: status,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('contact-value')),
        'new@example.test',
      );
      await tester.tap(find.byKey(const ValueKey('contact-submit')));
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
    });
  }

  testWidgets(
    'v0.18.138: a phone change sends installId + deviceCheck, bound to the '
    'number as sent (spaces and dashes taken out); a failing check still sends',
    (tester) async {
      final bound = <String>[];
      final sent = await open(
        tester,
        ContactKind.phone,
        (path) => path.endsWith('/change')
            ? {'sessionId': 'ses_1', 'retryAfterSeconds': 30}
            : {'phone': '+46701740633'},
        deviceFields: (app, phone) async {
          bound.add('$app|$phone');
          return {
            'installId': 'install-000000000001',
            'deviceCheck': {'platform': 'android', 'token': 't'},
          };
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('contact-value')),
        '+46 70-174 06 33',
      );
      await tester.tap(find.byKey(const ValueKey('contact-submit')));
      await tester.pumpAndSettle();
      expect(sent.single.$2, {
        'phone': '+46701740633',
        'installId': 'install-000000000001',
        'deviceCheck': {'platform': 'android', 'token': 't'},
      });
      expect(bound, ['rider|+46701740633']);
    },
  );

  testWidgets('v0.18.138: a throwing device check never stops the change', (
    tester,
  ) async {
    final sent = await open(
      tester,
      ContactKind.phone,
      (_) => {'sessionId': 'ses_1', 'retryAfterSeconds': 30},
      deviceFields: (_, _) async => throw StateError('no play services'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      '+46701740633',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.single.$2, {'phone': '+46701740633'});
  });

  testWidgets('v0.18.138: a national number with a trunk 0 and any '
      'separators goes out in E.164, as sign-in reads it', (tester) async {
    final sent = await open(
      tester,
      ContactKind.phone,
      (_) => {'sessionId': 'ses_1', 'retryAfterSeconds': 30},
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      '(070) 174-06.33',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.single.$2, {'phone': '+46701740633'});
  });

  for (final (typed, country, sent) in [
    // A French number on an en-US phone whose sign-in start country is France
    // (saved fix / last zone in France): read as sign-in reads it.
    ('06 12 34 56 78', 'FR', '+33612345678'),
    ('+46 (0)70 174 06 33', 'SE', '+46701740633'),
    ('+46 (0)70 174 06 33', 'FR', '+46701740633'),
  ]) {
    testWidgets('v0.18.138: "$typed" with start country $country -> $sent', (
      tester,
    ) async {
      final posts = await open(
        tester,
        ContactKind.phone,
        (_) => {'sessionId': 'ses_1', 'retryAfterSeconds': 30},
        startCountry: PhoneCountries.byIso(country),
      );
      await tester.enterText(
        find.byKey(const ValueKey('contact-value')),
        typed,
      );
      await tester.tap(find.byKey(const ValueKey('contact-submit')));
      await tester.pumpAndSettle();
      expect(posts.single.$2, {'phone': sent});
    });
  }
}
