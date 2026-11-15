import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/api_wallet_history.dart';
import 'package:movera_rider/features/wallet/data/api_wallet_repository.dart';
import 'package:movera_rider/features/wallet/data/switched_wallet_repository.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/wallet/domain/wallet_history.dart';
import 'package:movera_rider/features/wallet/presentation/wallet_history_section.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BQ-V41 = BQ-V20 (owner G12 Q5 "Real credit + limit",
/// decisions/driver-g12.md:12: "rider app wallet history shows 'Credit from
/// Movera'"; owner rule R2: the apps never work money out). The rider's
/// wallet history is the server's ledger, GET /wallet/entries
/// (openapi listWalletEntries: cursor + limit, `Page<WalletEntry>`
/// {items, nextCursor}); every amount is the server's Money in its
/// currency's decimals (SEK 2, TND 3); nothing is made on the phone on live.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => L10n.use('en'));

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  Map<String, Object?> entry(
    String id,
    String kind,
    int minor,
    String currency, {
    String? trip,
  }) => {
    'entryId': id,
    'ownerId': 'rdr_1',
    'amount': {'amountMinor': minor, 'currency': currency},
    'kind': kind,
    if (trip != null) 'tripId': trip,
    'at': '2026-11-14T10:00:00Z',
  };

  // Page 1: a Movera credit in kronor and a trip paid in dinars; page 2: a
  // refund in dinars.
  final page1 = {
    'items': [
      entry('wlt_3', 'adjustment', 12550, 'SEK'),
      entry('wlt_2', 'charge', -12345, 'TND', trip: 'trp_2'),
    ],
    'nextCursor': 'wlt_2',
  };
  final page2 = {
    'items': [entry('wlt_1', 'refund', 7500, 'TND', trip: 'trp_1')],
    'nextCursor': null,
  };

  ({ApiClient api, List<Uri> asked}) server(
    http.Response Function(Uri url) answer,
  ) {
    final asked = <Uri>[];
    return (
      api: ApiClient(
        env: staging,
        client: MockClient((request) async {
          asked.add(request.url);
          return answer(request.url);
        }),
      ),
      asked: asked,
    );
  }

  http.Response pages(Uri url) => http.Response(
    jsonEncode(url.queryParameters['cursor'] == 'wlt_2' ? page2 : page1),
    200,
    headers: {'content-type': 'application/json'},
  );

  group('ApiWalletHistory reads GET /wallet/entries', () {
    test('first page: limit, no cursor; the server Money as it is', () async {
      final s = server(pages);
      final history = ApiWalletHistory(api: s.api);
      final page = await history.load();
      expect(s.asked.single.path, '/api/v1/wallet/entries');
      expect(s.asked.single.queryParameters, {'limit': '50'});
      expect(page.nextCursor, 'wlt_2');
      expect(page.items.map((e) => e.id), ['wlt_3', 'wlt_2']);
      expect(page.items.first.kind, 'adjustment');
      expect(page.items.first.amount, const Money(12550, 'SEK'));
      expect(page.items.last.amount, const Money(-12345, 'TND'));
      expect(page.items.last.tripId, 'trp_2');
      expect(page.items.last.at, DateTime.utc(2026, 11, 14, 10));
      expect(history, isA<ServerBackedRepository>());
    });

    test('next page sends the server cursor; null ends the list', () async {
      final s = server(pages);
      final page = await ApiWalletHistory(api: s.api).load(cursor: 'wlt_2');
      expect(s.asked.single.queryParameters, {
        'limit': '50',
        'cursor': 'wlt_2',
      });
      expect(page.items.single.amount, const Money(7500, 'TND'));
      expect(page.nextCursor, isNull);
    });

    test('an entry without valid Money is left out, never guessed', () async {
      final s = server(
        (_) => http.Response(
          jsonEncode({
            'items': [
              {...entry('wlt_9', 'refund', 1, 'SEK'), 'amount': 12.5},
              entry('wlt_8', 'refund', 100, 'SEK'),
            ],
            'nextCursor': null,
          }),
          200,
        ),
      );
      final page = await ApiWalletHistory(api: s.api).load();
      expect(page.items.map((e) => e.id), ['wlt_8']);
    });

    test('a server error is an ApiError (the screen shows retry)', () async {
      final s = server((_) => http.Response('{"code":"internal"}', 500));
      await expectLater(
        ApiWalletHistory(api: s.api).load(),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('the label of each server kind, sv / fr / en', () {
    test('adjustment is "Credit from Movera" (contract walletCredit)', () {
      final want = {
        'en': 'Credit from Movera',
        'sv': 'Kredit från Movera',
        'fr': 'Crédit de Movera',
      };
      for (final lang in want.keys) {
        L10n.use(lang);
        expect(walletEntryLabel('adjustment', L10n.current), want[lang]);
      }
    });

    test('fee and debt_paid use the contract debtModel texts', () {
      L10n.use('sv');
      expect(walletEntryLabel('fee', L10n.current), 'Obetald avgift');
      expect(
        walletEntryLabel('debt_paid', L10n.current),
        'Obetald avgift betald',
      );
      L10n.use('fr');
      expect(walletEntryLabel('fee', L10n.current), 'Frais impayés');
      expect(
        walletEntryLabel('debt_paid', L10n.current),
        'Frais impayés réglés',
      );
      L10n.use('en');
      expect(walletEntryLabel('fee', L10n.current), 'Unpaid fee');
      expect(walletEntryLabel('debt_paid', L10n.current), 'Unpaid fee paid');
    });

    test('every other kind has its own text in every language', () {
      for (final lang in ['en', 'sv', 'fr']) {
        L10n.use(lang);
        final labels = {
          for (final kind in [
            'topup',
            'charge',
            'refund',
            'payout',
            'adjustment',
            'fee',
            'debt_paid',
          ])
            walletEntryLabel(kind, L10n.current),
        };
        expect(labels, hasLength(7), reason: lang);
        expect(
          walletEntryLabel('something_new', L10n.current),
          isNot(isIn(labels)),
          reason: '$lang: an unknown kind gets the general label',
        );
      }
      L10n.use('en');
      expect(walletEntryLabel('refund', L10n.current), 'Refund');
      expect(walletEntryLabel('charge', L10n.current), 'Trip payment');
    });
  });

  group('WalletHistorySection', () {
    Future<void> pump(WidgetTester tester, WalletHistorySource source) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WalletHistorySection(source: source),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the server label and the exact SEK / TND amounts, '
        'then the next page', (tester) async {
      final s = server(pages);
      await pump(tester, ApiWalletHistory(api: s.api));
      expect(find.text('Credit from Movera'), findsOneWidget);
      expect(find.text('Trip payment'), findsOneWidget);
      expect(find.text('+125,50 kr'), findsOneWidget);
      expect(find.text('-12.345 DT'), findsOneWidget);
      expect(find.text('Refund'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('wallet-history-more')));
      await tester.pumpAndSettle();
      expect(s.asked.last.queryParameters['cursor'], 'wlt_2');
      expect(find.text('Refund'), findsOneWidget);
      expect(find.text('+7.500 DT'), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-history-more')), findsNothing);
    });

    testWidgets('in Swedish', (tester) async {
      L10n.use('sv');
      await pump(tester, ApiWalletHistory(api: server(pages).api));
      expect(find.text('Kredit från Movera'), findsOneWidget);
      expect(find.text('+125,50 kr'), findsOneWidget);
    });

    testWidgets('no entries: the empty state', (tester) async {
      final s = server(
        (_) =>
            http.Response(jsonEncode({'items': [], 'nextCursor': null}), 200),
      );
      await pump(tester, ApiWalletHistory(api: s.api));
      expect(
        find.byKey(const ValueKey('wallet-history-empty')),
        findsOneWidget,
      );
      expect(find.text(L10n.current.walletHistoryEmpty), findsOneWidget);
    });

    testWidgets('an error shows retry; retry reads the server again', (
      tester,
    ) async {
      var fail = true;
      final s = server((url) => fail ? http.Response('{}', 503) : pages(url));
      await pump(tester, ApiWalletHistory(api: s.api));
      expect(find.text(L10n.current.walletHistoryLoadFailed), findsOneWidget);
      expect(find.text('Credit from Movera'), findsNothing);
      fail = false;
      await tester.tap(find.text(L10n.current.retry));
      await tester.pumpAndSettle();
      expect(find.text('Credit from Movera'), findsOneWidget);
    });
  });

  group('live: the phone builds no history and no balance', () {
    ApiClient wallet() => ApiClient(
      env: staging,
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/wallet') {
          final currency = request.url.queryParameters['currency'] ?? 'SEK';
          const balances = [
            {'amountMinor': 12550, 'currency': 'SEK'},
            {'amountMinor': 12345, 'currency': 'TND'},
          ];
          return http.Response(
            jsonEncode({
              'ownerId': 'rdr_1',
              'balance': balances.firstWhere(
                (b) => b['currency'] == currency,
                orElse: () => {'amountMinor': 0, 'currency': currency},
              ),
              'balances': balances,
              'updatedAt': '2026-11-14T10:00:00Z',
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    WalletController live() => WalletController(
      balances: SwitchedWalletRepository(
        on: ApiWalletRepository(api: wallet()),
        off: const DisabledWalletRepository(),
        isOn: () => true,
      ),
    );

    test('every balance is the server\'s (SEK and TND), as the live build '
        'composes it', () async {
      expect(await live().loadBalances(), const [
        Money(12550, 'SEK'),
        Money(12345, 'TND'),
      ]);
    });

    test('a trip charge and a refund add no phone-made history line', () async {
      final before = AppScope.instance.wallet.entries.length;
      final controller = live();
      await controller.chargeRide(previous: 0, amount: 25.9, rideId: 'trp_1');
      await controller.forCurrency('TND').refund(previous: 0, amount: 12.345);
      expect(AppScope.instance.wallet.entries.length, before);
    });
  });
}
