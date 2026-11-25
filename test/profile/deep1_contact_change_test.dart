import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_error.dart';
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

  // v0.18.165 (owner 2026-11-25 "Mail 90 s"): a new e-mail code before the
  // server's wait shows that wait (Retry-After), or a plain "wait" without it.
  for (final (wait, text) in [
    (const Duration(seconds: 45), 'Too many tries. Try again in '),
    (null, 'Too many tries. Wait a moment and try again.'),
  ]) {
    testWidgets('429 otp_resend_too_soon shows the wait ($wait)', (
      tester,
    ) async {
      await open(
        tester,
        ContactKind.email,
        (_) => throw ApiError(
          code: 'refused',
          reason: 'otp_resend_too_soon',
          message: 'x',
          statusCode: 429,
          retryAfter: wait,
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('contact-value')),
        'new@example.test',
      );
      await tester.tap(find.byKey(const ValueKey('contact-submit')));
      await tester.pumpAndSettle();
      expect(find.textContaining(text), findsOneWidget);
      if (wait != null) expect(find.textContaining('45'), findsOneWidget);
    });
  }
}
