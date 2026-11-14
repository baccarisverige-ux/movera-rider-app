import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/payments/presentation/pay_with_page.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/wallet/domain/rider_debt.dart';
import 'package:movera_rider/features/wallet/domain/wallet_ledger.dart';
import 'package:movera_rider/features/wallet/presentation/wallet_entry_label.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// J10 (contract v0.18.84 `debtModel`): the parts that use the J10 API
/// (`RideQuote.walletDebt`, `PayWithPage.walletOwed`, `RiderDebtRefusal`,
/// the wallet kinds `fee` / `debt_paid`). Before J10 this file does not
/// build.
Map<String, dynamic> get _contract =>
    jsonDecode(File('contracts/contract.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> get _texts =>
    (_contract['debtModel'] as Map)['texts'] as Map<String, dynamic>;

// Read once at the top (not inside a test case), like `_contract`: the
// contract copy is data, not app source (CI Phase 69 grep-style count).
String get _openapi => File('contracts/openapi.yaml').readAsStringSync();

Map<String, dynamic> _quote({Object? walletDebt}) => {
  'quoteId': 'qte_j10',
  'categoryId': 'economy',
  'total': {'amountMinor': 12900, 'currency': 'SEK'},
  'fareLines': [
    {
      'code': 'base',
      'amount': {'amountMinor': 12900, 'currency': 'SEK'},
    },
  ],
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 5))
      .toIso8601String(),
  'walletDebt': ?walletDebt,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RiderOutstanding.reset();
  });
  tearDown(() {
    RiderOutstanding.reset();
    L10n.use('en');
  });

  group('Quote.walletDebt (quoteInfo)', () {
    test('read as information: not in the total, no fare line', () {
      final quote = ApiQuoteRepository.contractQuoteOf(
        _quote(walletDebt: {'amountMinor': 3500, 'currency': 'SEK'}),
      )!;
      expect(quote.totalMinor, 12900);
      expect(quote.outstandingFeeMinor, 0);
      expect(quote.walletDebt, const Money(3500, 'SEK'));

      final selection = RideSelectionController(currency: 'SEK');
      addTearDown(selection.dispose);
      selection.adoptQuote('economy', quote);
      expect(selection.quoteDebtFor('economy'), const Money(3500, 'SEK'));
      expect(selection.unpaidFeeFor('economy'), isNull);
      expect(selection.priceFor('economy', 129), 129);
    });

    test('absent, zero or in another currency: no line', () {
      for (final debt in <Object?>[
        null,
        {'amountMinor': 0, 'currency': 'SEK'},
        {'amountMinor': 500, 'currency': 'EUR'},
      ]) {
        final quote = ApiQuoteRepository.contractQuoteOf(
          _quote(walletDebt: debt),
        )!;
        expect(quote.walletDebt, isNull, reason: '$debt');
      }
    });

    for (final language in ['en', 'fr', 'sv']) {
      test('[$language] the line is the contract text', () {
        L10n.use(language);
        final amount = formatMoney(const Money(3500, 'SEK'));
        expect(
          L10n.current.quoteDebtLine(amount),
          (_texts['quoteDebtLine'] as Map)[language].toString().replaceAll(
            '{amount}',
            amount,
          ),
        );
      });
    }
  });

  group('Pay with while the rider owes (walletSwitch)', () {
    Future<void> open(
      WidgetTester tester, {
      required double balance,
      Money? owed,
      List<bool>? flips,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PayWithPage(
            methods: const [
              PayWithMethod(brand: 'wallet', name: 'Wallet', detail: 'Wallet'),
              PayWithMethod(brand: 'cash', name: 'Cash', detail: 'Cash'),
            ],
            selectedBrand: 'cash',
            walletBalance: balance,
            promotion: null,
            brandMark: (_) => const SizedBox(width: 42, height: 38),
            useWalletFirst: false,
            onWalletFirstChanged: flips?.add,
            walletOwed: owed,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('"You owe X", the switch on and locked', (tester) async {
      final flips = <bool>[];
      await open(
        tester,
        balance: -35,
        owed: const Money(3500, 'SEK'),
        flips: flips,
      );
      expect(
        find.text('You owe ${formatMoney(const Money(3500, 'SEK'))}'),
        findsOneWidget,
      );
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('pay-with-wallet-first')),
      );
      expect(toggle.value, isTrue);
      expect(toggle.onChanged, isNull);
      await tester.tap(find.byKey(const ValueKey('pay-with-wallet-first')));
      await tester.pump();
      expect(flips, isEmpty);
    });

    testWidgets('nothing owed and no money: no wallet section', (tester) async {
      await open(tester, balance: 0);
      expect(find.byKey(const ValueKey('pay-with-wallet-first')), findsNothing);
      expect(find.byKey(const ValueKey('pay-with-wallet-owed')), findsNothing);
    });

    test('the controller gives Pay with the server\'s owed amount', () {
      final selection = RideSelectionController(currency: 'SEK')
        ..walletCurrency = 'SEK'
        ..setWalletBalance(-35);
      addTearDown(selection.dispose);
      expect(selection.walletOwed, const Money(3500, 'SEK'));
      expect(selection.walletFirstLocked, isTrue);
      expect(
        selection.walletSplitFor(12900).usesWallet,
        isFalse,
        reason: 'a debt is never split off the fare on the phone',
      );

      RiderOutstanding.current.value = const RiderOutstanding(
        byCurrency: [Money(2000, 'SEK')],
      );
      final owedOnly = RideSelectionController(currency: 'SEK');
      addTearDown(owedOnly.dispose);
      expect(owedOnly.walletOwed, const Money(2000, 'SEK'));
    });
  });

  group('rider_debt_above_max', () {
    ApiError refusal({List<String>? details}) => ApiError(
      code: 'conflict',
      message:
          'Trips paid in the car are paused until your unpaid fees '
          'are paid.',
      statusCode: 409,
      reason: 'rider_debt_above_max',
      details: details ?? const ['debt:84000 TND', 'max:84000 TND'],
    );

    test('the amount is the server\'s debt (TND, 3 decimals)', () {
      expect(RiderDebtRefusal.debtOf(refusal()), const Money(84000, 'TND'));
      expect(
        RiderDebtRefusal.messageOf(refusal()),
        (_texts['riderDebtAboveMax'] as Map)['en'].toString().replaceAll(
          '{amount}',
          formatMoney(const Money(84000, 'TND')),
        ),
      );
    });

    test('without a readable amount the server\'s words; another '
        'refusal is not this one', () {
      expect(
        RiderDebtRefusal.messageOf(refusal(details: const [])),
        refusal().message,
      );
      expect(
        RiderDebtRefusal.messageOf(
          const ApiError(
            code: 'conflict',
            message: 'x',
            reason: 'active_trip_exists',
          ),
        ),
        isNull,
      );
      expect(RiderDebtRefusal.messageOf(StateError('x')), isNull);
    });
  });

  group('wallet kinds fee and debt_paid', () {
    for (final language in ['en', 'fr', 'sv']) {
      test('[$language] each has its own label (contract texts)', () {
        L10n.use(language);
        expect(WalletEntryKind.fromWire('fee'), WalletEntryKind.fee);
        expect(WalletEntryKind.fromWire('debt_paid'), WalletEntryKind.debtPaid);
        expect(
          walletEntryLabel(WalletEntryKind.fee),
          (_texts['walletFee'] as Map)[language],
        );
        expect(
          walletEntryLabel(WalletEntryKind.debtPaid),
          (_texts['walletDebtPaid'] as Map)[language],
        );
      });
    }

    test('the kinds are the contract WalletEntry kinds', () {
      expect(_openapi, contains('          - fee\n          - debt_paid\n'));
    });
  });
}
