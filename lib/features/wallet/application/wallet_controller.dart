import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/analytics/analytics.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/payments/payment_gateway.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';
import 'package:movera_rider/features/wallet/domain/wallet_ledger.dart';

export 'package:movera_rider/features/wallet/data/wallet_repository.dart'
    show WalletPaymentSettings;

/// What happened to a wallet top-up, so the rider can be told whether they
/// were charged.
sealed class TopUpOutcome {
  const TopUpOutcome();
}

/// The payment went through and the balance is now [balance].
class TopUpCredited extends TopUpOutcome {
  const TopUpCredited(this.balance);
  final double balance;
}

/// Nothing was charged. [declined] when the payment provider answered no;
/// otherwise [error] says why the payment never went through.
class TopUpNotCharged extends TopUpOutcome {
  const TopUpNotCharged({this.error, this.declined = false});
  final Object? error;
  final bool declined;
}

/// The payment may or may not have gone through: confirming it failed and
/// its status could not be read either. Trying again with the same
/// idempotency key is safe; it can never charge twice.
class TopUpUnconfirmed extends TopUpOutcome {
  const TopUpUnconfirmed(this.error);
  final Object error;
}

class WalletController {
  /// [balances] is where the balance lives (ARCH-6); without it the
  /// device-local ledger over [store] is used, as before. AppScope passes
  /// the composed one, which release builds switch off.
  WalletController({
    WalletStore? store,
    PaymentGateway? gateway,
    WalletBalanceRepository? balances,
  }) : _store = store ?? WalletStore(),
       _gateway = gateway,
       _balancesOverride = balances;

  final WalletStore _store;
  final PaymentGateway? _gateway;
  final WalletBalanceRepository? _balancesOverride;
  late final WalletBalanceRepository _balances =
      _balancesOverride ?? LocalWalletRepository(_store, _store.currency);

  final Map<String, WalletController> _byCurrency = {};

  /// Q8: the rider has one wallet balance per currency and the app never
  /// converts. The controller of the balance in [currency] (this one when
  /// it already is); payment settings are shared.
  WalletController forCurrency(String currency) {
    if (currency == this.currency) return this;
    return _byCurrency.putIfAbsent(
      currency,
      () => WalletController(
        store: _store,
        gateway: _gateway,
        balances: _balances.inCurrency(currency),
      ),
    );
  }

  /// False when this build has no wallet (release until a server ledger
  /// exists).
  bool get available => _balances.available;

  /// The balance's currency. It pays only trips in the same currency.
  String get currency => _balances.currency;
  final Set<String> _topUpKeys = {};

  Future<WalletPaymentSettings> loadPayments() => _store.loadPayments();

  /// "Use wallet balance first" is a payment setting; these keep the rest
  /// of the settings as they are.
  Future<bool> loadUseWalletFirst() async =>
      (await _store.loadPayments()).useWalletFirst;

  /// Returns false, logged, when the setting could not be saved, so the
  /// caller can put its toggle back (CODE-16).
  Future<bool> saveUseWalletFirst(bool value) async {
    try {
      final current = await _store.loadPayments();
      await _store.savePayments(
        WalletPaymentSettings(
          defaultMethod: current.defaultMethod,
          business: current.business,
          extraMethods: current.extraMethods,
          useWalletFirst: value,
        ),
      );
      return true;
    } catch (error) {
      AppLog.warning(
        'wallet.use_wallet_first_save_failed',
        extra: {'error': '$error'},
      );
      return false;
    }
  }

  Future<void> savePayments(WalletPaymentSettings settings) =>
      _store.savePayments(settings);

  Future<double> loadBalance() => _balances.loadBalance();

  Future<TopUpOutcome> topUp({
    required double previous,
    required double amount,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? newIdempotencyKey('wallet');
    // ARCH-6: never take card money that nothing authoritative can credit.
    if (!_balances.available) {
      return const TopUpNotCharged(error: WalletUnavailableException());
    }
    if (_topUpKeys.contains(key)) return TopUpCredited(previous);
    _topUpKeys.add(key);
    final gateway = _gateway ?? AppScope.instance.paymentGateway;

    TopUpOutcome failed(TopUpOutcome outcome, Object? error, StackTrace? stack) {
      // Not credited: a retry with this key must reach the provider again
      // (its idempotency makes that safe) instead of being skipped here.
      _topUpKeys.remove(key);
      Analytics.paymentFailed();
      if (error != null) {
        AppScope.instance.crashes.record(
          error,
          stack ?? StackTrace.current,
          operation: 'wallet.topup',
        );
      }
      return outcome;
    }

    final PaymentIntent intent;
    try {
      intent = await gateway.create(
        amountMinor: Money.fromLegacyMajor(amount, currency).amountMinor,
        currency: currency,
        idempotencyKey: key,
        purpose: PaymentPurpose.walletTopUp,
      );
    } catch (error, stack) {
      // The provider may have created an intent before the response was lost.
      // Retry with the same idempotency key to recover its result safely.
      return failed(TopUpUnconfirmed(error), error, stack);
    }

    String status;
    try {
      status = await gateway.confirm(intent.id);
    } catch (error, stack) {
      // The confirmation may still have reached the provider. Ask before
      // telling the rider anything about their money.
      try {
        status = await gateway.status(intent.id);
      } catch (_) {
        return failed(TopUpUnconfirmed(error), error, stack);
      }
      if (status == 'processing') {
        return failed(TopUpUnconfirmed(error), error, stack);
      }
      if (status != 'succeeded') {
        return failed(TopUpNotCharged(error: error), error, stack);
      }
    }
    if (status == 'processing') {
      return failed(
        TopUpUnconfirmed(StateError('payment still processing')),
        null,
        null,
      );
    }
    if (status != 'succeeded') {
      return failed(const TopUpNotCharged(declined: true), null, null);
    }

    Analytics.track('payment_succeeded', extra: {'intent': intent.id});
    var next = previous + amount;
    try {
      next = await _balances.creditTopUp(
        paymentIntentId: intent.id,
        previous: previous,
        amount: amount,
      );
    } catch (error, stack) {
      // The money was taken: show it rather than hide it, and report that
      // the local copy could not be saved.
      AppScope.instance.crashes.record(
        error,
        stack,
        operation: 'wallet.topup.save',
      );
    }
    AppScope.instance.wallet.add(
      WalletEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        kind: WalletEntryKind.credit,
        amountMinor: Money.fromLegacyMajor(amount, currency).amountMinor,
        currency: currency,
        at: DateTime.now(),
      ),
    );
    return TopUpCredited(next);
  }

  /// Ride ids already deducted from the local balance, so a replayed
  /// payment event, a reload of the completion screen or a restored session
  /// can never charge the same ride twice.
  static const chargedRidesKey = 'movera_wallet_charged_rides';
  static const _chargedRidesKept = 50;
  static final Set<String> _chargesInFlight = {};

  /// True when the ride's payment method is the Movera Wallet. Snapshots carry
  /// either the brand id ('wallet') or its display name ('Movera Wallet').
  static bool isWalletPayment(String paymentMethod) =>
      paymentMethod.trim().toLowerCase().contains('wallet');

  /// Resolves the completed ride for [rideId] (the completion screen's
  /// remembered snapshot, else the persisted one) and charges it if it was
  /// paid from the wallet. See [chargeCompletedRide].
  Future<double?> chargeCompletedRideById(String rideId) async {
    final id = rideId.trim();
    final remembered = LastCompletedRide.value;
    final snapshot = remembered?.rideId?.trim() == id
        ? remembered
        : await RideSnapshotStore.readForArchive();
    return chargeCompletedRide(snapshot, rideId: id);
  }

  /// D-022: deducts a wallet-paid ride from the local balance once it has
  /// reached a charged status (paymentFinalized or later).
  ///
  /// [chargeRide] existed but had no callers, so wallet rides never reduced
  /// the balance. This makes the existing local ledger self-consistent; it
  /// does not make it authoritative — the balance is still a client-side
  /// value (R-043) until a server-owned ledger replaces [WalletStore].
  ///
  /// Returns the new balance, or null when nothing was charged (not a wallet
  /// ride, a different ride, no usable price, or already charged).
  Future<double?> chargeCompletedRide(
    RideSnapshot? snapshot, {
    required String rideId,
  }) async {
    final id = rideId.trim();
    if (id.isEmpty || snapshot == null || snapshot.rideId?.trim() != id) {
      return null;
    }
    if (!_balances.available) return null;
    // Q8: the trip is paid from the balance of its own currency.
    if (snapshot.currency != currency) {
      return forCurrency(
        snapshot.currency,
      ).chargeCompletedRide(snapshot, rideId: id);
    }
    // A wallet ride is charged in full; with "Use wallet balance first" the
    // wallet part booked with the ride is charged (never more than the
    // fare), and the method pays the rest.
    final double amount;
    // ARCH-9: the booked method id decides; the label only for snapshots
    // saved before ids were kept.
    final methodId = snapshot.paymentMethodId;
    final paidByWallet = methodId != null
        ? methodId == 'wallet'
        : isWalletPayment(snapshot.paymentMethod);
    if (paidByWallet) {
      amount = snapshot.price;
    } else if (snapshot.walletAmountMinor > 0) {
      final fareMinor = snapshot.fare.amountMinor;
      final part = snapshot.walletAmountMinor < fareMinor
          ? snapshot.walletAmountMinor
          : fareMinor;
      amount = Money(part, currency).major;
    } else {
      return null;
    }
    if (!amount.isFinite || amount <= 0) return null;
    if (!_chargesInFlight.add(id)) return null;
    try {
      final prefs = await PreferencesStore.load();
      final charged = prefs.getStringList(chargedRidesKey) ?? const <String>[];
      if (charged.contains(id)) return null;
      final kept = charged.length >= _chargedRidesKept
          ? charged.sublist(charged.length - _chargedRidesKept + 1)
          : charged;
      // Record first: a crash between the two writes must err towards not
      // charging twice rather than charging again on the next launch.
      await prefs.setStringList(chargedRidesKey, [...kept, id]);
      final previous = await _balances.loadBalance();
      final next = await chargeRide(
        previous: previous,
        amount: amount,
        rideId: id,
      );
      AppLog.info(
        'wallet.ride_charged',
        extra: {'rideId': id, 'amount': amount, 'localOnly': true},
      );
      return next;
    } finally {
      _chargesInFlight.remove(id);
    }
  }

  Future<double> chargeRide({
    required double previous,
    required double amount,
    String? rideId,
  }) async {
    final next = await _balances.debitRide(
      rideId: rideId,
      previous: previous,
      amount: amount,
    );
    AppScope.instance.wallet.add(
      WalletEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        kind: WalletEntryKind.ride,
        amountMinor: -Money.fromLegacyMajor(amount, currency).amountMinor,
        currency: currency,
        at: DateTime.now(),
      ),
    );
    return next;
  }

  Future<double> refund({
    required double previous,
    required double amount,
  }) async {
    final next = await _balances.refund(previous: previous, amount: amount);
    AppScope.instance.wallet.add(
      WalletEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        kind: WalletEntryKind.refund,
        amountMinor: Money.fromLegacyMajor(amount, currency).amountMinor,
        currency: currency,
        at: DateTime.now(),
      ),
    );
    return next;
  }
}
