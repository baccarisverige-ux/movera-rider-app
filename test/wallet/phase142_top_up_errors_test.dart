import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/payments/payment_gateway.dart';
import 'package:movera_rider/features/wallet/application/top_up_message.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemWallet extends WalletStore {
  double balance = 0;

  @override
  Future<double> loadBalance() async => balance;

  @override
  Future<void> saveBalance(double value) async {
    balance = value;
  }
}

/// A payment provider whose every answer the test decides.
class _ScriptedGateway implements PaymentGateway {
  final List<String> keys = [];
  Object? createError;
  Object? confirmError;
  String confirmStatus = 'succeeded';
  Object? statusError;
  String statusValue = 'succeeded';

  @override
  Future<PaymentIntent> create({
    required int amountMinor,
    required String currency,
    required String idempotencyKey,
    PaymentPurpose? purpose,
    String? rideId,
  }) async {
    keys.add(idempotencyKey);
    final error = createError;
    if (error != null) throw error;
    return PaymentIntent(
      id: 'pi_$idempotencyKey',
      amountMinor: amountMinor,
      currency: currency,
    );
  }

  @override
  Future<String> confirm(String intentId) async {
    final error = confirmError;
    if (error != null) throw error;
    return confirmStatus;
  }

  @override
  Future<String> status(String intentId) async {
    final error = statusError;
    if (error != null) throw error;
    return statusValue;
  }
}

const _offline = ApiError(code: 'NETWORK', message: 'no route to host');

/// Phase 142: a failed top-up used to show nothing. The rider is now told
/// whether they were charged, and a top-up whose result is unknown is never
/// reported as "not charged".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('top-up outcome', () {
    test('a lost creation response stays unconfirmed and can be '
        'retried with the same key', () async {
      final store = _MemWallet()..balance = 50;
      final gateway = _ScriptedGateway()..createError = _offline;
      final wallet = WalletController(store: store, gateway: gateway);

      final first = await wallet.topUp(
        previous: 50,
        amount: 200,
        idempotencyKey: 'top-a',
      );
      expect(first, isA<TopUpUnconfirmed>());
      expect((first as TopUpUnconfirmed).error, same(_offline));
      expect(store.balance, 50);

      gateway.createError = null;
      final retry = await wallet.topUp(
        previous: 50,
        amount: 200,
        idempotencyKey: 'top-a',
      );
      expect((retry as TopUpCredited).balance, 250);
      expect(gateway.keys, [
        'top-a',
        'top-a',
      ], reason: 'the retry reached the provider instead of being skipped');
      expect(store.balance, 250);
    });

    test('a declined payment is reported as declined', () async {
      final gateway = _ScriptedGateway()..confirmStatus = 'failed';
      final wallet = WalletController(store: _MemWallet(), gateway: gateway);
      final outcome = await wallet.topUp(previous: 0, amount: 100);
      expect(outcome, isA<TopUpNotCharged>());
      expect((outcome as TopUpNotCharged).declined, isTrue);
    });

    test('a lost confirmation that did go through is credited', () async {
      final store = _MemWallet();
      final gateway = _ScriptedGateway()
        ..confirmError = TimeoutException('confirm')
        ..statusValue = 'succeeded';
      final wallet = WalletController(store: store, gateway: gateway);
      final ledgerBefore = AppScope.instance.wallet.entries.length;

      final outcome = await wallet.topUp(previous: 0, amount: 100);

      expect((outcome as TopUpCredited).balance, 100);
      expect(store.balance, 100);
      expect(AppScope.instance.wallet.entries.length, ledgerBefore + 1);
    });

    test(
      'a lost confirmation that did not go through charges nothing',
      () async {
        final gateway = _ScriptedGateway()
          ..confirmError = TimeoutException('confirm')
          ..statusValue = 'requires_payment_method';
        final wallet = WalletController(store: _MemWallet(), gateway: gateway);
        final outcome = await wallet.topUp(previous: 0, amount: 100);
        expect(outcome, isA<TopUpNotCharged>());
        expect((outcome as TopUpNotCharged).declined, isFalse);
      },
    );

    test(
      'a confirmation nobody can check is unconfirmed, never "not charged"',
      () async {
        final store = _MemWallet();
        final gateway = _ScriptedGateway()
          ..confirmError = TimeoutException('confirm')
          ..statusError = _offline;
        final wallet = WalletController(store: store, gateway: gateway);
        final outcome = await wallet.topUp(previous: 0, amount: 100);
        expect(outcome, isA<TopUpUnconfirmed>());
        expect(store.balance, 0);
      },
    );
  });

  group('messages say whether the rider was charged', () {
    test('every failure that charged nothing says so', () {
      for (final outcome in <TopUpOutcome>[
        const TopUpNotCharged(error: _offline),
        const TopUpNotCharged(
          error: ApiError(code: 'X', message: '', statusCode: 429),
        ),
        const TopUpNotCharged(
          error: ApiError(code: 'X', message: '', statusCode: 503),
        ),
        TopUpNotCharged(error: StateError('bug')),
        const TopUpNotCharged(declined: true),
      ]) {
        expect(
          topUpMessage(outcome),
          contains("weren't charged"),
          reason: '$outcome',
        );
      }
    });

    test('an unconfirmed top-up never claims the rider was not charged', () {
      final message = topUpMessage(TopUpUnconfirmed(TimeoutException('x')))!;
      expect(message, isNot(contains("weren't charged")));
      expect(message, contains("won't charge you twice"));
    });

    test('a successful top-up needs no message', () {
      expect(topUpMessage(const TopUpCredited(100)), isNull);
    });
  });

  Future<void> openAndSimulate(WidgetTester tester) async {
    await tester.tap(find.text('Add funds (demo)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simulate top-up'));
    // The top-up starts once the sheet has finished closing.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> dismissMessage(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('a lost creation response does not claim no charge', (
    tester,
  ) async {
    final store = _MemWallet()..balance = 50;
    final gateway = _ScriptedGateway()..createError = _offline;
    await tester.pumpWidget(
      MaterialApp(
        home: WalletHome(
          wallet: WalletController(store: store, gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openAndSimulate(tester);

    expect(
      find.text(
        "We couldn't confirm your top-up. If it went through, it will "
        "show in your balance — trying again won't charge you twice.",
      ),
      findsOneWidget,
    );
    expect(store.balance, 50);
    await dismissMessage(tester);
  });

  testWidgets('retrying an unconfirmed top-up reuses its key, so it can '
      'never charge twice', (tester) async {
    final store = _MemWallet();
    final gateway = _ScriptedGateway()
      ..confirmError = TimeoutException('confirm')
      ..statusError = _offline;
    await tester.pumpWidget(
      MaterialApp(
        home: WalletHome(
          wallet: WalletController(store: store, gateway: gateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await openAndSimulate(tester);
    expect(
      find.textContaining("We couldn't confirm your top-up"),
      findsOneWidget,
    );
    expect(store.balance, 0);
    await dismissMessage(tester);

    // Back online: the rider simply tries again with the same amount.
    gateway
      ..confirmError = null
      ..statusError = null;
    await openAndSimulate(tester);
    await tester.pumpAndSettle();

    expect(gateway.keys, hasLength(2));
    expect(
      gateway.keys.last,
      gateway.keys.first,
      reason: 'the retry carries the first attempt\'s idempotency key',
    );
    expect(store.balance, 200);

    // A later, separate top-up gets a fresh key.
    await openAndSimulate(tester);
    await tester.pumpAndSettle();
    expect(gateway.keys, hasLength(3));
    expect(gateway.keys.last, isNot(gateway.keys.first));
    expect(store.balance, 400);
  });
}
