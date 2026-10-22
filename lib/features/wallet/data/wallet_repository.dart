import 'dart:async';

import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/features/wallet/domain/wallet_balance_repository.dart';

export 'package:movera_rider/features/wallet/domain/wallet_balance_repository.dart';

/// The wallet balance's source of truth.
///
/// [WalletStore] is the only implementation today, and it is client-local
/// (a double in SharedPreferences/localStorage): anyone with access to the
/// device or browser storage can edit it, and it is never synced against
/// what a backend actually charged or refunded. A real implementation
/// backed by a server-owned ledger must replace it before a release
/// composition may treat the balance as authoritative — see
/// `WalletComposition.validate`.
abstract class WalletBalanceSource {
  Future<double> loadBalance();
  Future<void> saveBalance(double value);
}

class WalletPaymentSettings {
  WalletPaymentSettings({
    required this.defaultMethod,
    required this.business,
    this.extraMethods = const [],
    bool? useWalletFirst,
  }) : _useWalletFirst = useWalletFirst;

  final String defaultMethod;
  final bool business;
  final List<Map<String, String>> extraMethods;

  /// Null when the caller did not set it: saving then keeps the stored
  /// choice instead of turning it back on (FLOW-3).
  final bool? _useWalletFirst;

  /// The wallet balance is taken off every fare first; the rest goes to
  /// the chosen method. On by default.
  bool get useWalletFirst => _useWalletFirst ?? true;
}

class WalletStore implements WalletBalanceSource {
  /// [currency]: which of the rider's balances this store reads (Q8: one
  /// per currency). The kronor balance keeps its original key.
  WalletStore({this.currency = Money.defaultCurrency});

  final String currency;

  static const balanceKey = 'movera_wallet_balance';

  /// Where the balance in [currency] is stored: [balanceKey] for kronor
  /// (unchanged), `movera_wallet_balance.EUR` and so on for the others.
  static String balanceKeyFor(String currency) =>
      currency == Money.defaultCurrency ? balanceKey : '$balanceKey.$currency';

  /// The store of the balance in [currency]; settings are shared.
  WalletStore inCurrency(String currency) =>
      currency == this.currency ? this : WalletStore(currency: currency);
  static const _legacyVoucherKeys = [
    'movera_voucher_code',
    'movera_voucher_amount',
    'movera_voucher_expires',
    'movera_used_vouchers',
  ];

  @override
  Future<double> loadBalance() async {
    final prefs = await PreferencesStore.load();
    return prefs.getDouble(balanceKeyFor(currency)) ?? 0;
  }

  @override
  Future<void> saveBalance(double value) async {
    final prefs = await PreferencesStore.load();
    await prefs.setDouble(balanceKeyFor(currency), value);
  }

  static const _removedMethods = {'paypal', 'klarna', 'swish'};

  Future<WalletPaymentSettings> loadPayments() async {
    final prefs = await PreferencesStore.load();
    await _removeLegacyVoucherState(prefs);
    // Earlier builds stored unverified cards and provider labels locally.
    // None represent tokenized or authorized payment methods.
    if (prefs.getString('movera_payment_methods') != null) {
      await prefs.remove('movera_payment_methods');
    }
    final savedDefault = prefs.getString('movera_default_payment');
    // Cash is the default; removed methods (PayPal, Klarna, Swish)
    // and unverified local cards fall back to it.
    final defaultMethod = savedDefault == null ||
            _removedMethods.contains(savedDefault) ||
            savedDefault == 'card' ||
            savedDefault.startsWith('card_')
        ? 'cash'
        : savedDefault;
    if (savedDefault != defaultMethod) {
      await prefs.setString('movera_default_payment', defaultMethod);
    }
    return WalletPaymentSettings(
      defaultMethod: defaultMethod,
      business: prefs.getBool('movera_payment_business') ?? false,
      useWalletFirst: prefs.getBool(walletFirstKey) ?? true,
    );
  }

  /// The default method as it is stored: removed methods (PayPal, Klarna,
  /// Swish) and unverified local cards are Cash.
  static String storableDefault(String method) =>
      _removedMethods.contains(method) ||
          method == 'card' ||
          method.startsWith('card_')
      ? 'cash'
      : method;

  Future<void> savePayments(WalletPaymentSettings settings) async {
    final prefs = await PreferencesStore.load();
    await _removeLegacyVoucherState(prefs);
    await prefs.setString(
      'movera_default_payment',
      storableDefault(settings.defaultMethod),
    );
    await prefs.setBool('movera_payment_business', settings.business);
    // Only an explicit choice is written; settings built without it (the
    // Wallet screen saving a default method) keep the rider's opt-out.
    final walletFirst = settings._useWalletFirst;
    if (walletFirst != null) await prefs.setBool(walletFirstKey, walletFirst);
    await prefs.remove('movera_payment_methods');
  }

  /// The Personal/Business choice alone; the default method is not touched.
  Future<void> saveBusiness(bool business) async {
    final prefs = await PreferencesStore.load();
    await prefs.setBool('movera_payment_business', business);
  }

  static const walletFirstKey = 'movera_wallet_first';

  /// Demo flavour only: a rider with 50 kr in the wallet, so the split
  /// payment can be seen on GitHub Pages. A stored balance is never touched.
  static Future<void> seedDemoBalance({double kr = 50}) async {
    final prefs = await PreferencesStore.load();
    if (prefs.getDouble(balanceKey) != null) return;
    await prefs.setDouble(balanceKey, kr);
  }

  /// Every balance the device holds, by currency (Q8), kronor first.
  static Future<Map<String, double>> balancesByCurrency() async {
    final prefs = await PreferencesStore.load();
    final out = <String, double>{
      Money.defaultCurrency: prefs.getDouble(balanceKey) ?? 0,
    };
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('$balanceKey.')) continue;
      final code = key.substring(balanceKey.length + 1);
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) continue;
      out[code] = prefs.getDouble(key) ?? 0;
    }
    return out;
  }

  Future<void> _removeLegacyVoucherState(dynamic prefs) async {
    for (final key in _legacyVoucherKeys) {
      await prefs.remove(key);
    }
  }
}

/// The device-local ledger behind [WalletStore] (demo/dev only). It is not
/// `ServerBackedRepository`, so a release composition that exposes the
/// wallet with it fails (ARCH-6).
///
/// RC-10: like the server ledger it stands in for, it ignores the
/// `previous` balance the caller passes. Each movement re-reads the stored
/// balance and writes it back inside one serialized section, in öre, so a
/// ride charge or a refund that lands while the Wallet page is open is
/// never overwritten by a top-up computed from the page's stale balance.
class LocalWalletRepository implements WalletBalanceRepository {
  LocalWalletRepository([WalletBalanceSource? source, this.currency = Money.defaultCurrency])
      : _source = source ?? WalletStore(currency: currency);

  final WalletBalanceSource _source;

  /// Q8: the balance of [currency] is its own store. A [WalletStore] source
  /// moves to that currency's key; any other source (a test's) is only
  /// used for its own currency, and the other currencies use the device's
  /// stores.
  @override
  WalletBalanceRepository inCurrency(String currency) {
    if (currency == this.currency) return this;
    final source = _source;
    return LocalWalletRepository(
      source is WalletStore
          ? source.inCurrency(currency)
          : WalletStore(currency: currency),
      currency,
    );
  }

  /// The movement in progress, shared by every instance: they all write the
  /// one stored balance. Cleared as soon as that movement ends.
  static Future<void>? _running;

  @override
  bool get available => true;

  /// The currency of this balance (one ledger per currency, Q8).
  @override
  final String currency;

  @override
  Future<double> loadBalance() => _source.loadBalance();

  /// Applies [deltaKr] to the stored balance, serialized with every other
  /// movement, and returns the new balance.
  Future<double> _apply(double deltaKr) async {
    final previous = _running;
    final done = Completer<void>();
    _running = done.future;
    try {
      if (previous != null) await previous;
      final current = await _source.loadBalance();
      final nextMinor = Money.fromLegacyMajor(current, currency).amountMinor +
          Money.fromLegacyMajor(deltaKr, currency).amountMinor;
      final next = Money(nextMinor, currency).major;
      await _source.saveBalance(next);
      return next;
    } finally {
      done.complete();
      if (identical(_running, done.future)) _running = null;
    }
  }

  @override
  Future<double> creditTopUp({
    required String paymentIntentId,
    required double previous,
    required double amount,
  }) => _apply(amount);

  @override
  Future<double> debitRide({
    String? rideId,
    required double previous,
    required double amount,
  }) => _apply(-amount);

  @override
  Future<double> refund({
    required double previous,
    required double amount,
  }) => _apply(amount);
}

/// The wallet of a build where it is switched off: no balance, and every
/// movement refused before any money moves. Release composes this until a
/// server ledger exists.
class DisabledWalletRepository
    implements WalletBalanceRepository, FeatureOffRepository {
  const DisabledWalletRepository([this.currency = Money.defaultCurrency]);

  @override
  bool get available => false;

  @override
  final String currency;

  @override
  WalletBalanceRepository inCurrency(String currency) =>
      DisabledWalletRepository(currency);

  @override
  Future<double> loadBalance() async => 0;

  @override
  Future<double> creditTopUp({
    required String paymentIntentId,
    required double previous,
    required double amount,
  }) => Future.error(const WalletUnavailableException());

  @override
  Future<double> debitRide({
    String? rideId,
    required double previous,
    required double amount,
  }) => Future.error(const WalletUnavailableException());

  @override
  Future<double> refund({
    required double previous,
    required double amount,
  }) => Future.error(const WalletUnavailableException());
}
