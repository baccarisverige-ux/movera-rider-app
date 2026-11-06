import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/auth_controller.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Job A12 (owner 2026-11-05, "Remove everywhere"): the sign-in screen has
/// no "Test numbers" link, button or list in any build, and no build bakes
/// MOVERA_TEST_NUMBERS into the app.

const _words = ['Test numbers', 'Numéros de test', 'Testnummer'];

Iterable<File> _files(String dir, bool Function(String) keep) => Directory(
  dir,
).listSync(recursive: true).whereType<File>().where((f) => keep(f.path));

void main() {
  test('no app code, string or build reads MOVERA_TEST_NUMBERS', () {
    final hits = <String>[
      for (final f in [
        ..._files('lib', (p) => p.endsWith('.dart') || p.endsWith('.arb')),
        ..._files('.github/workflows', (p) => p.endsWith('.yml')),
      ])
        if (f.readAsStringSync().contains('MOVERA_TEST_NUMBERS=') ||
            f.readAsStringSync().contains(
              "fromEnvironment('MOVERA_TEST_NUMBERS')",
            ))
          f.path,
    ];
    expect(hits, isEmpty);
  });

  test('no sign-in test-numbers text in any language', () {
    final hits = <String>[
      for (final f in _files(
        'lib',
        (p) => p.endsWith('.arb') || p.endsWith('.dart'),
      ))
        for (final w in [..._words, 'testNumbersButton', 'auth-test-numbers'])
          if (f.readAsStringSync().contains(w)) '${f.path}: $w',
    ];
    expect(hits, isEmpty);
  });

  for (final locale in const ['en', 'fr', 'sv']) {
    testWidgets('$locale: the sign-in screen shows no test-numbers widget '
        'even when the server would list test accounts', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tokens = MemoryTokenStore();
      final api = ApiClient(
        env: const AppEnv(
          flavor: AppFlavor.staging,
          apiBaseUrl: 'https://api.test.movera.invalid',
        ),
        client: MockClient(
          (request) async => request.url.path == '/api/v1/auth/test-accounts'
              ? http.Response(
                  '{"accounts":[{"phone":"+46700000001","app":"rider",'
                  '"status":"test"}]}',
                  200,
                  headers: {'content-type': 'application/json'},
                )
              : http.Response('{"code":"not_found"}', 404),
        ),
        tokens: tokens,
      );
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SignIn(
              controller: AuthController(
                auth: AuthRepository(api: api, tokens: tokens),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      for (final w in _words) {
        expect(find.textContaining(w), findsNothing);
      }
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              '${(w.key! as ValueKey).value}'.startsWith('auth-test-'),
        ),
        findsNothing,
      );
    });
  }
}
