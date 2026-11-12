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
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:movera_rider/features/profile/domain/account_security.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/profile/presentation/contact_change.dart';
import 'package:movera_rider/features/profile/presentation/personal_info.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every PATCH /rider/profile body the app sends.
class _PatchSpy extends InProcessMockClient {
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method == 'PATCH' &&
        request.url.path == SyncedProfileRepository.path &&
        request is http.Request) {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
    }
    return super.send(request);
  }
}

/// G30 (owner 2026-11-12 13:41 "fix everything like must be now", contract
/// v0.18.76 `contract.json#emailVerified`): the rider profile carries
/// `emailVerifiedAt` (absent = Not verified); Account and Personal info show
/// the e-mail with the existing Verified / Not verified labels; the phone
/// stays the value alone (the server has no phone date); the e-mail code
/// start answers `delivery` and only 'sent' means a code went out (Rule 35);
/// `PATCH /rider/profile` never carries an e-mail.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );
  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );

  Map<String, Object?> rider({String? email = 'ada@example.com', String? at}) =>
      {
        'riderId': 'rdr_1',
        'firstName': 'Ada',
        'phone': '+21620123456',
        'email': ?email,
        'emailVerifiedAt': ?at,
        'status': 'active',
        'version': 3,
        'consents': <String, Object?>{},
      };

  AccountSecurityController liveSecurity(Map<String, Object?> body) =>
      AccountSecurityController(
        built: false,
        readsRiderProfile: true,
        repository: AccountSecurityRepository(
          api: ApiClient(
            env: live,
            client: MockClient((request) async {
              if (request.url.path != '/api/v1/rider/profile') {
                return http.Response(jsonEncode({'code': 'not_found'}), 404);
              }
              return http.Response(jsonEncode(body), 200);
            }),
          ),
        ),
      );

  Future<void> pumpPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, _) => MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProfileController profile(String key) =>
      ProfileController(store: ProfileRepository(storageKey: key));

  test('G30: fromRiderProfile reads emailVerifiedAt; the phone stays '
      'unknown', () {
    final verified = AccountSecurityState.fromRiderProfile(
      rider(at: '2026-11-12T13:41:00.000Z'),
    );
    expect(verified.emailVerifiedAt, DateTime.utc(2026, 11, 12, 13, 41));
    expect(verified.emailVerified, isTrue);
    final notVerified = AccountSecurityState.fromRiderProfile(rider());
    expect(notVerified.emailVerified, isFalse);
    // A date without an e-mail proves nothing.
    expect(
      AccountSecurityState.fromRiderProfile(
        rider(email: null, at: '2026-11-12T13:41:00.000Z'),
      ).emailVerified,
      isFalse,
    );
    expect(verified.phoneVerifiedAt, isNull);
  });

  testWidgets('G30: live Account shows "ada@example.com · Verified" when the '
      'profile has emailVerifiedAt', (tester) async {
    await pumpPhone(
      tester,
      AccountHomePage(
        controller: profile('g30_a'),
        securityController: liveSecurity(rider(at: '2026-11-12T13:41:00.000Z')),
      ),
    );
    expect(find.text('ada@example.com · Verified'), findsOneWidget);
    expect(find.text('ada@example.com'), findsNothing);
  });

  testWidgets('G30: live Account and Personal info show "· Not verified" '
      'without emailVerifiedAt; the phone line is the number alone', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      AccountHomePage(
        controller: profile('g30_b'),
        securityController: liveSecurity(rider()),
      ),
    );
    expect(find.text('ada@example.com · Not verified'), findsOneWidget);

    await pumpPhone(
      tester,
      PersonalInfoPage(
        controller: profile('g30_c'),
        securityController: liveSecurity(rider()),
      ),
    );
    expect(find.text('ada@example.com · Not verified'), findsOneWidget);
    expect(find.text('+21620123456'), findsOneWidget);
    expect(find.textContaining('+21620123456 ·'), findsNothing);
  });

  testWidgets('G30: live Personal info with a verified e-mail says Verified; '
      'no e-mail still reads "not added"', (tester) async {
    await pumpPhone(
      tester,
      PersonalInfoPage(
        controller: profile('g30_d'),
        securityController: liveSecurity(rider(at: '2026-11-12T13:41:00.000Z')),
      ),
    );
    expect(find.text('ada@example.com · Verified'), findsOneWidget);

    await pumpPhone(
      tester,
      AccountHomePage(
        controller: profile('g30_e'),
        securityController: liveSecurity(rider(email: null)),
      ),
    );
    expect(find.text(L10n.current.emailNotAdded), findsOneWidget);
  });

  Future<List<(String, Map<String, dynamic>)>> openChange(
    WidgetTester tester,
    Map<String, dynamic> Function(String path) answer,
  ) async {
    final sent = <(String, Map<String, dynamic>)>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ContactChangePage(
          kind: ContactKind.email,
          post: (path, body) async {
            sent.add((path, body));
            return answer(path);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sent;
  }

  const notSentYet = 'E-mail codes cannot be sent yet. Try again later.';

  testWidgets('G30: delivery pending_provider shows the "cannot be sent yet" '
      'text, no code field and never "we sent a code"', (tester) async {
    final sent = await openChange(
      tester,
      (_) => {
        'challengeId': 'emc_1',
        'expiresAt': '2026-11-12T18:00:00Z',
        'delivery': 'pending_provider',
      },
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      'ny@example.test',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.single.$1, '/api/v1/account/email/change');
    expect(find.text(notSentYet), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-code')), findsNothing);
    expect(find.textContaining('code to'), findsNothing);
    expect(find.text('We send a code to the new e-mail.'), findsNothing);
  });

  testWidgets('G30 (Rule 35): an answer without delivery (an older server) '
      'is not a sent code either', (tester) async {
    await openChange(tester, (_) => {'challengeId': 'emc_1'});
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      'ny@example.test',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(find.text(notSentYet), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-code')), findsNothing);
  });

  testWidgets('G30: delivery sent names the address and asks for the code; an '
      'old verify answer without emailVerifiedAt still saves', (tester) async {
    final sent = await openChange(
      tester,
      (path) => path.endsWith('/change')
          ? {'challengeId': 'emc_1', 'delivery': 'sent'}
          : {'email': 'ny@example.test'},
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      'ny@example.test',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(find.text('We sent a code to ny@example.test.'), findsOneWidget);
    expect(find.text(notSentYet), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('contact-code')),
      '123456',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(sent.last.$1, '/api/v1/account/email/verify');
    expect(sent.last.$2, {'challengeId': 'emc_1', 'code': '123456'});
    expect(find.text('E-mail changed'), findsOneWidget);
  });

  testWidgets('G30: a gone challenge (invalid_email_challenge) says the code '
      'expired', (tester) async {
    await openChange(
      tester,
      (path) => path.endsWith('/change')
          ? {'challengeId': 'emc_1', 'delivery': 'sent'}
          : throw const ApiError(
              code: 'invalid_request',
              reason: 'invalid_email_challenge',
              message: 'x',
              statusCode: 400,
            ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('contact-value')),
      'ny@example.test',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('contact-code')),
      '000000',
    );
    await tester.tap(find.byKey(const ValueKey('contact-submit')));
    await tester.pumpAndSettle();
    expect(find.text(L10n.current.codeExpired), findsOneWidget);
  });

  test('G30: PATCH /rider/profile body never has email, also after the '
      'profile e-mail changed', () async {
    final spy = _PatchSpy();
    final controller = ProfileController(
      store: SyncedProfileRepository(
        api: ApiClient(client: spy, env: demo),
      ),
    );
    await controller.hydrate();
    final changed = controller.profile.copyWith(
      name: 'Ada',
      email: 'new@example.com',
    );
    expect(
      SyncedProfileRepository.body(changed).keys.toSet().difference({
        'expectedVersion',
        'firstName',
        'language',
        'consents',
      }),
      isEmpty,
    );
    await controller.update(changed);
    expect(spy.bodies, isNotEmpty);
    for (final body in spy.bodies) {
      expect(body.containsKey('email'), isFalse, reason: '$body');
    }
  });

  test('G30: the in-process mock refuses PATCH /rider/profile with email '
      '(400 invalid_request email_needs_code), nothing saved', () async {
    final mock = InProcessMockClient();
    final api = ApiClient(client: mock, env: demo);
    await expectLater(
      api.patch(
        '/api/v1/rider/profile',
        body: {'expectedVersion': 1, 'email': 'x@example.com'},
      ),
      throwsA(
        isA<ApiError>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.code, 'code', 'invalid_request')
            .having((e) => e.reason, 'reason', 'email_needs_code'),
      ),
    );
    expect(mock.riderProfile, isNull);
  });

  test('G30: the in-process mock starts an e-mail check with delivery sent '
      'and its verify records emailVerifiedAt', () async {
    final mock = InProcessMockClient();
    final api = ApiClient(client: mock, env: demo);
    final start = await api.post(
      '/api/v1/account/email/change',
      body: {'email': 'Ada@Example.com'},
    );
    expect(start['delivery'], 'sent');
    final done = await api.post(
      '/api/v1/account/email/verify',
      body: {'challengeId': start['challengeId'], 'code': '1234'},
    );
    expect(done['email'], 'ada@example.com');
    expect(DateTime.tryParse('${done['emailVerifiedAt']}'), isNotNull);
    expect(mock.accountSecurity['email'], 'ada@example.com');
    expect(mock.accountSecurity['emailVerifiedAt'], done['emailVerifiedAt']);
  });

  test('G30: the new texts equal contract.json#emailVerified.texts (en, fr, '
      'sv)', () {
    final contract =
        jsonDecode(File('contracts/contract.json').readAsStringSync())
            as Map<String, dynamic>;
    final texts =
        (contract['emailVerified'] as Map<String, dynamic>)['texts']
            as Map<String, dynamic>;
    for (final lang in ['en', 'fr', 'sv']) {
      final arb =
          jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
              as Map<String, dynamic>;
      expect(
        arb['contactCodeNotSentYet'],
        (texts['codeNotSentYet'] as Map)[lang],
        reason: lang,
      );
      expect(
        arb['valueVerified'],
        '{value} · ${(texts['verified'] as Map)[lang]}',
        reason: lang,
      );
      expect(
        arb['valueNotVerified'],
        '{value} · ${(texts['notVerified'] as Map)[lang]}',
        reason: lang,
      );
    }
  });
}
