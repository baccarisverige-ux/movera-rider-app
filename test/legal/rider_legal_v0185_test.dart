import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/core/legal/rider_legal.dart';
import 'package:movera_rider/features/content/presentation/content_gate.dart';
import 'package:movera_rider/features/profile/presentation/account_widgets.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.18.5 §30 `legal`, owner G1-B2 "Real texts from admin
/// (Recommended)": the terms and privacy policy per country from
/// `GET /legal/{country}`, two separate links, re-accept on a new version.

const _env = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.test.movera.invalid',
);

http.Response _json(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// The contract's own draft texts for [country], as the server answers
/// them at version 0 (placeholders unfilled are left to the server).
Map<String, Object?> _answer(
  String country, {
  int version = 0,
  bool reaccept = false,
}) {
  final contract =
      jsonDecode(File('contracts/contract.json').readAsStringSync()) as Map;
  final defaults = contract['legal']['defaults'][country] as Map;
  return {
    'country': country,
    'version': version,
    'source': version == 0 ? 'default' : 'admin',
    'reaccept': reaccept,
    'terms': defaults['terms'],
    'privacy': defaults['privacy'],
  };
}

class _Server {
  _Server(this.answer);
  final Map<String, Object?> Function() answer;
  final List<http.Request> requests = [];
  int acceptStatus = 204;

  http.Client get client => MockClient((request) async {
    requests.add(request);
    if (request.url.path.startsWith('/api/v1/legal/')) {
      return _json(200, answer());
    }
    if (request.url.path == '/api/v1/account/legal/accept') {
      return acceptStatus == 204
          ? http.Response('', 204)
          : _json(acceptStatus, {
              'code': 'conflict',
              'message': 'x',
              'reason': 'terms_version_not_current',
            });
    }
    return _json(404, {'code': 'not_found', 'message': 'x'});
  });
}

Future<(RiderLegalController, _Server, ValueNotifier<bool>)> _controller(
  Map<String, Object?> Function() answer, {
  String country = 'SE',
  bool signedIn = true,
}) async {
  final server = _Server(answer);
  final tokens = MemoryTokenStore();
  if (signedIn) await tokens.save(access: 'a', refresh: 'r');
  final onTrip = ValueNotifier(false);
  final legal = RiderLegalController(
    api: ApiClient(env: _env, client: server.client, tokens: tokens),
    store: MemoryLegalStore(),
    onTrip: onTrip,
    country: () async => country,
  );
  return (legal, server, onTrip);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => L10n.use('en'));

  test(
    'GET /legal/{country} goes out before sign-in, without a token',
    () async {
      expect(ApiClient.needsSession('/api/v1/legal/SE'), isFalse);
      final (legal, server, _) = await _controller(
        () => _answer('FR'),
        country: 'FR',
        signedIn: false,
      );
      await legal.load(start: true);
      expect(server.requests.single.url.path, '/api/v1/legal/FR');
      expect(server.requests.single.headers['Authorization'], isNull);
      expect(legal.texts!.country, 'FR');
      // Paragraphs are separated by a blank line; version 0 starts with the
      // lawyer-review line.
      final first = legal.texts!.terms.paragraphsIn('en').first;
      expect(first, startsWith('Draft'));
    },
  );

  test('the last answer is kept for offline use', () async {
    final store = MemoryLegalStore();
    var online = true;
    final legal = RiderLegalController(
      api: ApiClient(
        env: _env,
        client: MockClient((_) async {
          if (!online) throw http.ClientException('offline');
          return _json(200, _answer('SE'));
        }),
        tokens: MemoryTokenStore(),
      ),
      store: store,
      country: () async => 'SE',
    );
    await legal.load(start: true);
    online = false;
    final again = RiderLegalController(
      api: legal.api,
      store: store,
      country: () async => 'SE',
    );
    await again.load(start: true);
    expect(again.texts?.terms.titleIn('sv'), legal.texts!.terms.titleIn('sv'));
    expect(again.failed, isFalse);
  });

  test('re-accept: a new version with reaccept asks once; "I accept" posts '
      '{ country, version } with an Idempotency-Key', () async {
    final (legal, server, onTrip) = await _controller(
      () => _answer('SE', version: 3, reaccept: true),
    );
    await legal.load(start: true);
    expect(legal.mustAccept, isFalse, reason: 'not signed in yet');
    legal.signedIn();
    expect(legal.mustAccept, isTrue);
    onTrip.value = true;
    expect(legal.mustAccept, isFalse, reason: 'never during a trip');
    onTrip.value = false;

    expect(await legal.accept(), isTrue);
    final post = server.requests.last;
    expect(post.url.path, '/api/v1/account/legal/accept');
    expect(jsonDecode(post.body), {'country': 'SE', 'version': 3});
    expect(post.headers['Idempotency-Key'], isNotEmpty);
    expect(legal.mustAccept, isFalse);
  });

  test('version 0 or no reaccept: nothing to accept', () async {
    final (legal, _, _) = await _controller(() => _answer('SE'));
    legal.signedIn();
    await legal.load(start: true);
    expect(legal.mustAccept, isFalse);
    final (other, _, _) = await _controller(() => _answer('SE', version: 2));
    other.signedIn();
    await other.load(start: true);
    expect(other.mustAccept, isFalse);
  });

  test('a version published mid-session waits for the next start; a '
      'booking refused with terms_not_accepted shows it at once', () async {
    var version = 1;
    final (legal, _, _) = await _controller(
      () => _answer('SE', version: version, reaccept: version > 1),
    );
    legal.signedIn();
    await legal.load(start: true);
    version = 2;
    await legal.load(); // coming back to the foreground
    expect(legal.mustAccept, isFalse);
    await legal.onTermsNotAccepted();
    expect(legal.mustAccept, isTrue);
  });

  test(
    '409 terms_version_not_current reloads and asks for the new one',
    () async {
      var version = 2;
      final (legal, server, _) = await _controller(
        () => _answer('SE', version: version, reaccept: true),
      );
      legal.signedIn();
      await legal.load(start: true);
      version = 3;
      server.acceptStatus = 409;
      expect(await legal.accept(), isFalse);
      expect(legal.toAccept?.version, 3);
    },
  );

  testWidgets('Terms and Privacy pages show the server texts in the app '
      'language, not the old sample texts', (tester) async {
    final (legal, _, _) = await _controller(() => _answer('FR'), country: 'FR');
    await tester.runAsync(() => legal.load(start: true));
    L10n.use('fr');
    for (final kind in ['terms', 'privacy']) {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AccountLegalPage(kind: kind, legal: legal),
        ),
      );
      await tester.pump();
      final doc = legal.texts!.of(kind);
      expect(find.text(doc.titleIn('fr')), findsOneWidget);
      expect(find.text(doc.paragraphsIn('fr').first), findsOneWidget);
      expect(find.textContaining('Who we are'), findsNothing);
    }
  });

  testWidgets('the re-accept screen shows both texts and "I accept"', (
    tester,
  ) async {
    final (legal, server, _) = await _controller(
      () => _answer('SE', version: 4, reaccept: true),
    );
    legal.signedIn();
    await tester.runAsync(() => legal.load(start: true));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LegalAcceptScreen(
          texts: legal.toAccept!,
          onAccept: legal.accept,
          onCallSos: () {},
        ),
      ),
    );
    expect(find.text(legal.texts!.terms.titleIn('en')), findsOneWidget);
    expect(find.text(L10n.current.contentTermsAccept), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('legal-accept-button')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(server.requests.last.url.path, '/api/v1/account/legal/accept');
    expect(legal.mustAccept, isFalse);
  });

  test(
    'checker MEDIUM 3: a second rider on the same app run is asked; '
    'a booking refused with terms_not_accepted always shows the terms',
    () async {
      final (legal, _, _) = await _controller(
        () => _answer('SE', version: 5, reaccept: true),
      );
      legal.signedIn();
      await legal.load(start: true);
      expect(await legal.accept(), isTrue);
      expect(legal.mustAccept, isFalse);

      // Rider A signs out; rider B signs in without a restart.
      legal.signedOut();
      legal.signedIn();
      expect(legal.mustAccept, isTrue, reason: 'B never accepted version 5');

      // Even when this device believes it was accepted, the server's 409
      // terms_not_accepted shows the terms.
      expect(await legal.accept(), isTrue);
      expect(legal.mustAccept, isFalse);
      await legal.onTermsNotAccepted();
      expect(legal.mustAccept, isTrue);
      expect(legal.toAccept?.version, 5);
      expect(await legal.accept(), isTrue);
      expect(legal.mustAccept, isFalse);
    },
  );
}
