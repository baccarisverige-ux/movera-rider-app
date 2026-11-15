import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/wallet/application/rider_refunds_repository.dart';
import 'package:movera_rider/features/wallet/domain/rider_refund.dart';
import 'package:movera_rider/features/wallet/presentation/refund_choice_page.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BQ-V39 rider part (contract.json#debtModel.refunds, owner Q-M4
/// decisions/session-2026-11-06.md:1102): a refund starts with no
/// destination; the rider is told by the refund notice (bell + push, kind
/// refund) and reads GET /rider/refunds; he chooses with
/// POST /rider/refunds/{refundId}/destination among the server's `choices`
/// only (a card refund does not exist yet: card company not chosen). The
/// amount is the server's Money, shown in its currency's decimals.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => L10n.use('en'));

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  Map<String, Object?> refundWire({
    String id = 'rfd_1',
    String trip = 'trp_1',
    int minor = 12550,
    String currency = 'SEK',
    String? destination,
    List<String>? choices = const ['wallet', 'swish', 'bank'],
    String? payoutStatus,
  }) => {
    'refundId': id,
    'tripId': trip,
    'amount': {'amountMinor': minor, 'currency': currency},
    'reason': 'Driver took a long way',
    'status': 'done',
    'destination': destination,
    'payoutStatus': payoutStatus,
    'createdAt': '2026-11-14T10:00:00Z',
    if (choices != null) 'choices': choices,
  };

  final sek = refundWire();
  final tnd = refundWire(
    id: 'rfd_2',
    trip: 'trp_2',
    minor: 12350,
    currency: 'TND',
    choices: const ['wallet', 'bank'],
  );

  ({
    RiderRefundsRepository repo,
    List<http.Request> requests,
    List<http.Response Function(http.Request)> answers,
  })
  server(List<Map<String, Object?>> items) {
    final requests = <http.Request>[];
    final answers = <http.Response Function(http.Request)>[];
    final api = ApiClient(
      env: staging,
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({'items': items, 'nextCursor': null}),
            200,
          );
        }
        if (answers.isNotEmpty) return answers.removeAt(0)(request);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final id =
            request.url.pathSegments[request.url.pathSegments.length - 2];
        final item = items.firstWhere((i) => i['refundId'] == id);
        final method = body['method'] as String;
        return http.Response(
          jsonEncode(
            {
              ...item,
              'destination': method,
              'payoutStatus': method == 'wallet' ? null : 'pending',
              'choices': null,
            }..removeWhere((k, v) => k == 'choices'),
          ),
          200,
        );
      }),
    );
    return (
      repo: RiderRefundsRepository(api: api),
      requests: requests,
      answers: answers,
    );
  }

  http.Response error(int status, String code, String reason, String msg) =>
      http.Response(
        jsonEncode({'code': code, 'message': msg, 'reason': reason}),
        status,
      );

  group('RiderRefund.fromWire', () {
    test('SEK: the server amount, waiting while destination is null', () {
      final r = RiderRefund.fromWire(sek)!;
      expect(r.refundId, 'rfd_1');
      expect(r.tripId, 'trp_1');
      expect(r.amount, const Money(12550, 'SEK'));
      expect(r.waiting, isTrue);
      expect(r.choices, [
        RefundChoice.wallet,
        RefundChoice.swish,
        RefundChoice.bank,
      ]);
      expect(r.swedishBank, isTrue);
    });

    test('TND: 3 decimals kept, wallet and bank (IBAN) only', () {
      final r = RiderRefund.fromWire(tnd)!;
      expect(r.amount, const Money(12350, 'TND'));
      expect(r.choices, [RefundChoice.wallet, RefundChoice.bank]);
      expect(r.swedishBank, isFalse);
    });

    test('a choice the app does not know (a later card) is never offered', () {
      final r = RiderRefund.fromWire(
        refundWire(choices: const ['card', 'wallet']),
      )!;
      expect(r.choices, [RefundChoice.wallet]);
    });

    test('chosen or without choices: not waiting', () {
      expect(
        RiderRefund.fromWire(
          refundWire(destination: 'wallet', choices: null),
        )!.waiting,
        isFalse,
      );
      expect(
        RiderRefund.fromWire(refundWire(choices: const []))!.waiting,
        isFalse,
      );
      expect(RiderRefund.fromWire({'refundId': 'x'}), isNull);
    });
  });

  group('RiderRefundsRepository', () {
    test('reads GET /rider/refunds and keeps the waiting ones', () async {
      final s = server([
        sek,
        refundWire(id: 'rfd_9', destination: 'bank', choices: null),
      ]);
      final waiting = await s.repo.waiting();
      expect(s.requests.single.method, 'GET');
      expect(s.requests.single.url.path, '/api/v1/rider/refunds');
      expect(waiting.map((r) => r.refundId), ['rfd_1']);
      expect((await s.repo.waiting(tripId: 'trp_1')).map((r) => r.refundId), [
        'rfd_1',
      ]);
      expect(await s.repo.waiting(tripId: 'trp_other'), isEmpty);
    });

    test('wallet: POST destination with an Idempotency-Key', () async {
      final s = server([sek]);
      final done = await s.repo.choose(
        'rfd_1',
        const RefundDestinationChoice.wallet(),
      );
      final post = s.requests.single;
      expect(post.method, 'POST');
      expect(post.url.path, '/api/v1/rider/refunds/rfd_1/destination');
      expect(jsonDecode(post.body), {'method': 'wallet'});
      expect(
        post.headers['Idempotency-Key'],
        startsWith('refund-destination-'),
      );
      expect(done.destination, 'wallet');
      expect(done.waiting, isFalse);
    });

    test('a retry after a lost answer sends the same key', () async {
      final s = server([sek]);
      s.answers.add((_) => error(503, 'unavailable', 'unavailable', 'Busy'));
      await expectLater(
        s.repo.choose('rfd_1', const RefundDestinationChoice.wallet()),
        throwsA(isA<ApiError>()),
      );
      await s.repo.choose('rfd_1', const RefundDestinationChoice.wallet());
      expect(s.requests, hasLength(2));
      expect(
        s.requests[0].headers['Idempotency-Key'],
        s.requests[1].headers['Idempotency-Key'],
      );
      // Another choice is another request.
      final s2 = server([sek]);
      await s2.repo.choose(
        'rfd_1',
        RefundDestinationChoice.swish(phone: '+46701234567'),
      );
      expect(
        s2.requests.single.headers['Idempotency-Key'],
        isNot(s.requests[0].headers['Idempotency-Key']),
      );
    });

    test('SE bank: clearing + account; TN bank: IBAN', () async {
      final s = server([sek, tnd]);
      await s.repo.choose(
        'rfd_1',
        RefundDestinationChoice.swedishBank(
          clearingNumber: '8327',
          accountNumber: '9123456',
          holderName: 'Sara Ek',
        ),
      );
      expect(jsonDecode(s.requests.last.body), {
        'method': 'bank',
        'bank': {
          'clearingNumber': '8327',
          'accountNumber': '9123456',
          'holderName': 'Sara Ek',
        },
      });
      await s.repo.choose(
        'rfd_2',
        RefundDestinationChoice.iban(
          iban: 'TN59 1000 6035 1835 9847 8831',
          holderName: 'Amine Ben Ali',
        ),
      );
      expect(jsonDecode(s.requests.last.body), {
        'method': 'bank',
        'bank': {
          'iban': 'TN59 1000 6035 1835 9847 8831',
          'holderName': 'Amine Ben Ali',
        },
      });
    });
  });

  group('the refund push', () {
    test('kind refund opens the refund of its trip', () {
      final push = PushPayload.fromMap({
        'kind': 'refund',
        'deepLink': 'movera://trips/trp_1/receipt',
        'tripId': 'trp_1',
      });
      expect(push.routedRefundTripId, 'trp_1');
      expect(push.destination, PushDestination.refund);
    });

    test('another kind with a receipt link is not a refund', () {
      final push = PushPayload.fromMap({
        'kind': 'receipt',
        'deepLink': 'movera://trips/trp_1/receipt',
      });
      expect(push.routedRefundTripId, isNull);
      expect(push.destination, PushDestination.ride);
    });
  });

  Future<List<Object?>> pumpPage(
    WidgetTester tester,
    RiderRefundsRepository repo,
    Map<String, Object?> wire, {
    String lang = 'en',
  }) async {
    L10n.use(lang);
    final popped = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  popped.add(
                    await Navigator.of(context).push<Object?>(
                      MaterialPageRoute(
                        builder: (_) => RefundChoicePage(
                          refund: RiderRefund.fromWire(wire)!,
                          repository: repo,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return popped;
  }

  group('RefundChoicePage', () {
    testWidgets('SEK: 125,50 kr; wallet, Swish and bank', (tester) async {
      final s = server([sek]);
      await pumpPage(tester, s.repo, sek);
      expect(find.text('125,50 kr'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('refund-choice-wallet')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('refund-choice-swish')), findsOneWidget);
      expect(find.byKey(const ValueKey('refund-choice-bank')), findsOneWidget);
      expect(s.requests, isEmpty);
    });

    testWidgets('TND: 12.350 DT; no Swish; a card choice never shows', (
      tester,
    ) async {
      final wire = refundWire(
        id: 'rfd_2',
        minor: 12350,
        currency: 'TND',
        choices: const ['wallet', 'bank', 'card'],
      );
      final s = server([wire]);
      await pumpPage(tester, s.repo, wire, lang: 'fr');
      expect(find.text('12.350 DT'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('refund-choice-wallet')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('refund-choice-bank')), findsOneWidget);
      expect(find.byKey(const ValueKey('refund-choice-swish')), findsNothing);
      expect(find.byKey(const ValueKey('refund-choice-card')), findsNothing);
    });

    testWidgets('the send button waits for a choice', (tester) async {
      final s = server([sek]);
      await pumpPage(tester, s.repo, sek);
      final send = tester.widget<FilledButton>(
        find.byKey(const ValueKey('refund-choice-send')),
      );
      expect(send.onPressed, isNull);
    });

    testWidgets('wallet: one POST, then back with the chosen refund', (
      tester,
    ) async {
      final s = server([sek]);
      final popped = await pumpPage(tester, s.repo, sek);
      await tester.tap(find.byKey(const ValueKey('refund-choice-wallet')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('refund-choice-send')));
      await tester.pumpAndSettle();
      expect(
        s.requests.single.url.path,
        '/api/v1/rider/refunds/rfd_1/destination',
      );
      expect(jsonDecode(s.requests.single.body), {'method': 'wallet'});
      expect(popped.single, isA<RiderRefund>());
      expect((popped.single! as RiderRefund).destination, 'wallet');
    });

    testWidgets('TND bank: IBAN form, holder required before sending', (
      tester,
    ) async {
      final s = server([tnd]);
      final popped = await pumpPage(tester, s.repo, tnd);
      await tester.tap(find.byKey(const ValueKey('refund-choice-bank')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('refund-clearing')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('refund-iban')),
        'TN59 1000 6035 1835 9847 8831',
      );
      await tester.tap(find.byKey(const ValueKey('refund-choice-send')));
      await tester.pumpAndSettle();
      expect(s.requests, isEmpty);
      expect(find.text(L10n.current.refundFieldInvalid), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('refund-holder')),
        'Amine Ben Ali',
      );
      await tester.tap(find.byKey(const ValueKey('refund-choice-send')));
      await tester.pumpAndSettle();
      expect(jsonDecode(s.requests.single.body), {
        'method': 'bank',
        'bank': {
          'iban': 'TN59 1000 6035 1835 9847 8831',
          'holderName': 'Amine Ben Ali',
        },
      });
      expect(popped.single, isA<RiderRefund>());
    });

    testWidgets('SEK Swish: a +46 number', (tester) async {
      final s = server([sek]);
      await pumpPage(tester, s.repo, sek, lang: 'sv');
      await tester.tap(find.byKey(const ValueKey('refund-choice-swish')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('refund-swish-phone')),
        '0701234567',
      );
      await tester.tap(find.byKey(const ValueKey('refund-choice-send')));
      await tester.pumpAndSettle();
      expect(s.requests, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('refund-swish-phone')),
        '+46701234567',
      );
      await tester.tap(find.byKey(const ValueKey('refund-choice-send')));
      await tester.pumpAndSettle();
      expect(jsonDecode(s.requests.single.body), {
        'method': 'swish',
        'swish': {'phone': '+46701234567'},
      });
    });

    testWidgets('409 destination_chosen: told, then back', (tester) async {
      final s = server([sek]);
      s.answers.add(
        (_) => error(409, 'conflict', 'destination_chosen', 'Already chosen.'),
      );
      final popped = await pumpPage(tester, s.repo, sek);
      await tester.tap(find.byKey(const ValueKey('refund-choice-wallet')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('refund-choice-send')));
      await tester.pump();
      await tester.pump();
      expect(find.text(L10n.current.refundAlreadyChosen), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(popped.single, isTrue);
    });

    testWidgets('400 bank_details_invalid stays with a hint', (tester) async {
      final s = server([sek]);
      s.answers.add(
        (_) => error(400, 'invalid_request', 'bank_details_invalid', 'IBAN'),
      );
      await pumpPage(tester, s.repo, sek);
      await tester.tap(find.byKey(const ValueKey('refund-choice-bank')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('refund-clearing')),
        '8327',
      );
      await tester.enterText(
        find.byKey(const ValueKey('refund-account')),
        '9123456',
      );
      await tester.enterText(
        find.byKey(const ValueKey('refund-holder')),
        'Sara Ek',
      );
      await tester.tap(find.byKey(const ValueKey('refund-choice-send')));
      await tester.pumpAndSettle();
      expect(find.text(L10n.current.refundDetailsInvalid), findsOneWidget);
      expect(find.byType(RefundChoicePage), findsOneWidget);
    });

    testWidgets('server busy: try again sends the same key', (tester) async {
      final s = server([sek]);
      s.answers.add((_) => error(503, 'unavailable', 'unavailable', 'Busy'));
      final popped = await pumpPage(tester, s.repo, sek);
      await tester.tap(find.byKey(const ValueKey('refund-choice-wallet')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('refund-choice-send')));
      await tester.pumpAndSettle();
      expect(find.text(L10n.current.refundSendFailed), findsOneWidget);
      expect(find.byType(RefundChoicePage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('refund-choice-send')));
      await tester.pumpAndSettle();
      expect(s.requests, hasLength(2));
      expect(
        s.requests[0].headers['Idempotency-Key'],
        s.requests[1].headers['Idempotency-Key'],
      );
      expect(popped.single, isA<RiderRefund>());
    });
  });

  group('RefundsWaitingCard', () {
    Future<void> pumpCard(
      WidgetTester tester,
      RiderRefundsRepository repo,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: RefundsWaitingCard(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a waiting SEK refund shows its amount', (tester) async {
      final s = server([sek]);
      await pumpCard(tester, s.repo);
      expect(
        find.byKey(const ValueKey('refund-waiting-rfd_1')),
        findsOneWidget,
      );
      expect(find.textContaining('125,50 kr'), findsOneWidget);
    });

    testWidgets('a waiting TND refund shows 3 decimals', (tester) async {
      final s = server([tnd]);
      await pumpCard(tester, s.repo);
      expect(find.textContaining('12.350 DT'), findsOneWidget);
    });

    testWidgets('nothing waiting: nothing shown', (tester) async {
      final s = server([refundWire(destination: 'wallet', choices: null)]);
      await pumpCard(tester, s.repo);
      expect(find.byType(InkWell), findsNothing);
      expect(find.textContaining('kr'), findsNothing);
    });
  });
}
