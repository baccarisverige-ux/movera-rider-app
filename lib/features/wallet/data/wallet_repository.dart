import 'dart:async';

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
  static const balanceKey = 'movera_wallet_balance';
  static const _legacyVoucherKeys = [
    'movera_voucher_code',
    'movera_voucher_amount',
    'movera_voucher_expires',
    'movera_used_vouchers',
  ];

  @override
  Future<double> loadBalance() async {
    final prefs = await PreferencesStore.load();
    return prefs.getDouble(balanceKey) ?? 0;
  }

  @override
  Future<void> saveBalance(double value) async {
    final prefs = await PreferencesStore.load();
    await prefs.setDouble(balanceKey, value);
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
    // Pay in car is the default; removed methods (PayPal, Klarna, Swish)
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

  Future<void> savePayments(WalletPaymentSettings settings) async {
    final prefs = await PreferencesStore.load();
    await _removeLegacyVoucherState(prefs);
    final method = settings.defaultMethod;
    await prefs.setString(
      'movera_default_payment',
      _removedMethods.contains(method) || method == 'card' ||
              method.startsWith('card_')
          ? 'cash'
          : method,
    );
    await prefs.setBool('movera_payment_business', settings.business);
    // Only an explicit choice is written; settings built without it (the
    // Wallet screen saving a default method) keep the rider's opt-out.
    final walletFirst = settings._useWalletFirst;
    if (walletFirst != null) await prefs.setBool(walletFirstKey, walletFirst);
    await prefs.remove('movera_payment_methods');
  }

  static const walletFirstKey = 'movera_wallet_first';

  /// Demo flavour only: a rider with 50 kr in the wallet, so the split
  /// payment can be seen on GitHub Pages. A stored balance is never touched.
  static Future<void> seedDemoBalance({double kr = 50}) async {
    final prefs = await PreferencesStore.load();
    if (prefs.getDouble(balanceKey) != null) return;
    await prefs.setDouble(balanceKey, kr);
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
  LocalWalletRepository([WalletBalanceSource? source])
      : _source = source ?? WalletStore();

  final WalletBalanceSource _source;

  /// The movement in progress, shared by every instance: they all write the
  /// one stored balance. Cleared as soon as that movement ends.
  static Future<void>? _running;

  @override
  bool get available => true;

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
      final nextMinor = (current * 100).round() + (deltaKr * 100).round();
      final next = nextMinor / 100;
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
  const DisabledWalletRepository();

  @override
  bool get available => false;

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
