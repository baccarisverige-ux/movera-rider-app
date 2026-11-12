import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/contact_change.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G30 (contract v0.18.76 `emailVerified.verifyCurrent` / `apps.rider`):
/// tapping a Not verified e-mail opens the code check with the address
/// filled and read-only; "Send code" posts that address to
/// `/account/email/change`, the code to `/account/email/verify`, and the
/// account is read again (the line turns Verified).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  Future<List<(String, Map<String, dynamic>)>> openVerify(
    WidgetTester tester,
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
          kind: ContactKind.email,
          verifyCurrent: 'ada@example.com',
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

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const ValueKey('contact-value')));

  testWidgets('G30: verify-current: the address is filled and read-only; '
      'send posts it, the code verifies it, "E-mail verified"', (tester) async {
    var saved = 0;
    final sent = await openVerify(
      tester,
      (path) => path.endsWith('/change')
          ? {'challengeId': 'emc_1', 'delivery': 'sent'}
          : {
              'email': 'ada@example.com',
              'emailVerifiedAt': '2026-11-12T18:00:00.000Z',
            },
      saved: () => saved++,
    );
    expect(find.text('Verify e-mail'), findsOneWidget);
    expect(field(tester).controller!.text, 'ada@example.com');
    expect(field(tester).readOnly, isTrue);
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.single.$1, '/api/v1/account/email/change');
    expect(sent.single.$2, {'email': 'ada@example.com'});
    expect(find.text('We sent a code to ada@example.com.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('contact-code')),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.last.$1, '/api/v1/account/email/verify');
    expect(sent.last.$2, {'challengeId': 'emc_1', 'code': '123456'});
    expect(saved, 1);
    expect(find.text('E-mail verified'), findsOneWidget);
    expect(find.text('E-mail changed'), findsNothing);
  });

  testWidgets('G30: verify-current with pending_provider says codes cannot be '
      'sent yet and shows no code field', (tester) async {
    await openVerify(
      tester,
      (_) => {'challengeId': 'emc_1', 'delivery': 'pending_provider'},
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('E-mail codes cannot be sent yet. Try again later.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('contact-code')), findsNothing);
  });

  testWidgets('G30: "Change e-mail" in verify-current mode empties the field '
      'and makes it editable; a new address is then sent', (tester) async {
    final sent = await openVerify(
      tester,
      (_) => {'challengeId': 'emc_2', 'delivery': 'sent'},
    );
    await tester.tap(find.byKey(const ValueKey('contact-change-instead')));
    await tester.pumpAndSettle();
    expect(field(tester).readOnly, isFalse);
    expect(field(tester).controller!.text, isEmpty);
    expect(find.text('Change e-mail'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      'ny@example.test',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.single.$2, {'email': 'ny@example.test'});
  });

  Map<String, Object?> rider({String? at}) => {
    'riderId': 'rdr_1',
    'firstName': 'Ada',
    'phone': '+21620123456',
    'email': 'ada@example.com',
    'emailVerifiedAt': ?at,
    'status': 'active',
    'version': 3,
    'consents': <String, Object?>{},
  };

  Future<(List<(String, Map<String, dynamic>)>, AccountSecurityController)>
  openPersonalInfo(WidgetTester tester, {String? at}) async {
    var verifiedAt = at;
    final security = AccountSecurityController(
      built: false,
      readsRiderProfile: true,
      repository: AccountSecurityRepository(
        api: ApiClient(
          env: live,
          client: MockClient(
            (request) async => request.url.path == '/api/v1/rider/profile'
                ? http.Response(jsonEncode(rider(at: verifiedAt)), 200)
                : http.Response(jsonEncode({'code': 'not_found'}), 404),
          ),
        ),
      ),
    );
    final sent = <(String, Map<String, dynamic>)>[];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, _) => MaterialApp(
          home: PersonalInfoPage(
            controller: ProfileController(
              store: ProfileRepository(storageKey: 'g30_v_$at'),
            ),
            securityController: security,
            contactPost: (path, body) async {
              sent.add((path, body));
              if (path.endsWith('/change')) {
                return {'challengeId': 'emc_9', 'delivery': 'sent'};
              }
              verifiedAt = '2026-11-12T18:00:00.000Z';
              return {
                'email': 'ada@example.com',
                'emailVerifiedAt': verifiedAt,
              };
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (sent, security);
  }

  testWidgets('G30: tapping a Not verified e-mail in Personal info opens the '
      'check with the address filled; after the code it reads Verified', (
    tester,
  ) async {
    final (sent, _) = await openPersonalInfo(tester);
    await tester.tap(find.text('ada@example.com · Not verified'));
    await tester.pumpAndSettle();
    expect(find.byType(ContactChangePage), findsOneWidget);
    expect(field(tester).controller!.text, 'ada@example.com');
    expect(field(tester).readOnly, isTrue);
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-code')),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.map((s) => s.$1), [
      '/api/v1/account/email/change',
      '/api/v1/account/email/verify',
    ]);
    expect(sent.first.$2, {'email': 'ada@example.com'});
    expect(find.byType(ContactChangePage), findsNothing);
    expect(find.text('ada@example.com · Verified'), findsOneWidget);
  });

  testWidgets('G30: a Verified e-mail opens the normal change (empty, '
      'editable field)', (tester) async {
    await openPersonalInfo(tester, at: '2026-11-12T13:41:00.000Z');
    await tester.tap(find.text('ada@example.com · Verified'));
    await tester.pumpAndSettle();
    expect(find.byType(ContactChangePage), findsOneWidget);
    expect(field(tester).controller!.text, isEmpty);
    expect(field(tester).readOnly, isFalse);
  });
}
