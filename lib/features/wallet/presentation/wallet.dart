import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/application/card_entry_policy.dart';
import 'package:movera_rider/features/payments/presentation/add_card_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/zone_settings.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/wallet/application/top_up_message.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/l10n/l10n.dart';

Future<void> showVoucherUnavailableSheet(BuildContext context) async {
  const ink = Color(0xFF11181D);
  const muted = Color(0xFF5C656C);

  await MoveraSheet.show<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.confirmation_number_outlined,
                color: ink,
                size: 34,
              ),
              const SizedBox(height: 14),
              Text(
                context.l10n.vouchersNotYet,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.vouchersNotYetBody,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: muted,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// One destination for the wallet balance and ride payment preferences.
class WalletAndPaymentsScreen extends StatefulWidget {
  const WalletAndPaymentsScreen({super.key, this.initialTab = 0});

  /// 0 = wallet, 1 = payment preferences.
  final int initialTab;

  @override
  State<WalletAndPaymentsScreen> createState() =>
      _WalletAndPaymentsScreenState();
}

class _WalletAndPaymentsScreenState extends State<WalletAndPaymentsScreen> {
  late int _tab = widget.initialTab;

  /// FLOW-17: bumped each time Payments is shown, so it re-reads the
  /// balance a top-up on the Wallet tab just changed.
  int _paymentsVisits = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: context.l10n.back,
                  ),
                  Expanded(
                    child: Text(
                      context.l10n.walletAndPayments,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final (index, title) in [
                    (0, context.l10n.menuWallet),
                    (1, context.l10n.payments),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: OutlinedButton(
                          onPressed: () => setState(() {
                            if (index == 1 && _tab != 1) _paymentsVisits++;
                            _tab = index;
                          }),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _tab == index
                                ? const Color(0xFF11181D)
                                : Colors.white,
                            foregroundColor: _tab == index
                                ? Colors.white
                                : const Color(0xFF11181D),
                          ),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  const WalletHome(embedded: true),
                  WalletScreen(embedded: true, refreshToken: _paymentsVisits),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletHome extends StatefulWidget {
  const WalletHome({super.key, this.wallet, this.embedded = false});

  final WalletController? wallet;
  final bool embedded;

  @override
  State<WalletHome> createState() => _WalletHomeState();
}

class _WalletHomeState extends State<WalletHome> {
  static const Color _ink = Color(0xFF11181D);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _line = Color(0xFFE6E8E7);
  late final WalletController _baseWallet =
      widget.wallet ?? AppScope.instance.walletController;

  /// Q8: one balance per currency. The one shown is the rider's current
  /// zone's; the chips switch between the zones' currencies.
  String _currency = Money.defaultCurrency;
  WalletController get _wallet => _baseWallet.forCurrency(_currency);
  bool get _demoPayments => AppScope.instance.environment.allowsMockTransport;

  /// Demo top-up amounts in whole units of the shown currency.
  static const _topUpAmounts = <String, List<int>>{
    'SEK': [100, 200, 500],
    'EUR': [10, 20, 50],
    'TND': [30, 60, 150],
  };
  List<int> get _topUps => _topUpAmounts[_currency] ?? const [100, 200, 500];

  String _money(num major) =>
      formatMoney(Money.fromLegacyMajor(major, _currency), whole: true);

  double _balance = 0;
  bool _loading = true;
  bool _failed = false;
  bool _topUpBusy = false;

  /// A top-up whose result is unknown. Retrying the same amount reuses its
  /// idempotency key, so the retry can never become a second charge.
  ({String key, int amount})? _unconfirmedTopUp;

  @override
  void initState() {
    super.initState();
    _currency = _baseWallet.currency;
    _restore();
    _followCurrentZone();
  }

  /// Shows the balance of the zone the rider is in (last location fix).
  Future<void> _followCurrentZone() async {
    final zone = await currentRiderZone();
    if (!mounted || zone.currency == _currency || _topUpBusy) return;
    _switchCurrency(zone.currency);
  }

  void _switchCurrency(String currency) {
    if (currency == _currency || _topUpBusy) return;
    setState(() {
      _currency = currency;
      _unconfirmedTopUp = null;
    });
    _restore();
  }

  Widget _currencyChips() {
    final codes = [for (final zone in RiderZones.all) zone.currency];
    return Wrap(
      spacing: 6,
      children: [
        for (final code in codes)
          Semantics(
            button: true,
            selected: code == _currency,
            label: context.l10n.balanceIn(code),
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('wallet-currency-$code'),
              onTap: () => _switchCurrency(code),
              borderRadius: BorderRadius.circular(99),
              // A 44 pt target around the small pill.
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: code == _currency
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      code,
                      style: _style(
                        11,
                        weight: FontWeight.w700,
                        color: code == _currency ? _ink : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  TextStyle _style(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
    double? height,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  Future<void> _restore() async {
    if (!mounted) return;
    if (!_loading || _failed) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final currency = _currency;
    try {
      final balance = await _wallet.loadBalance();
      if (!mounted || currency != _currency) return;
      setState(() {
        _balance = balance;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || currency != _currency) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _topUp(int amount, String idempotencyKey) async {
    final outcome = await _wallet.topUp(
      previous: _balance,
      amount: amount.toDouble(),
      idempotencyKey: idempotencyKey,
    );
    _unconfirmedTopUp = outcome is TopUpUnconfirmed
        ? (key: idempotencyKey, amount: amount)
        : null;
    if (!mounted) return;
    if (outcome is TopUpCredited) {
      setState(() => _balance = outcome.balance);
      return;
    }
    final message = topUpMessage(outcome);
    if (message != null) MoveraToast.show(context, message);
  }

  Future<void> _openAddFunds() async {
    if (!_demoPayments || _topUpBusy) return;
    // After an unconfirmed top-up the same amount is offered again.
    final amounts = _topUps;
    int amount = _unconfirmedTopUp?.amount ?? amounts[1];
    final funded = await MoveraSheet.show<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _line,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.addFunds,
                      style: _style(20, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.demoTopUpNote,
                      style: _style(12, weight: FontWeight.w400, color: _muted),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        for (final value in amounts) ...[
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setSheetState(() => amount = value),
                              child: Container(
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: amount == value
                                      ? _ink
                                      : const Color(0xFFF4F5F4),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  _money(value),
                                  style: _style(
                                    13,
                                    weight: FontWeight.w600,
                                    color: amount == value
                                        ? Colors.white
                                        : _ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (value != amounts.last) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        child: Text(context.l10n.simulateTopUp),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (funded != true || !mounted) return;
    // One key for the whole submit path, so a retry of this same intent
    // never creates a second charge. Retrying an unconfirmed top-up of the
    // same amount reuses that top-up's key for the same reason.
    final pending = _unconfirmedTopUp;
    final idempotencyKey = pending != null && pending.amount == amount
        ? pending.key
        : newIdempotencyKey('wallet');
    setState(() => _topUpBusy = true);
    try {
      await _topUp(amount, idempotencyKey);
    } finally {
      if (mounted) setState(() => _topUpBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.embedded)
                Row(
                  children: [
                    Semantics(
                      button: true,
                      label: context.l10n.back,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          customBorder: const CircleBorder(),
                          child: const SizedBox(
                            width: 42,
                            height: 42,
                            child: Icon(Icons.arrow_back_rounded, color: _ink),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        context.l10n.menuWallet,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _style(16, weight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 42),
                  ],
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 196,
                width: double.infinity,
                child: Image.asset(
                  excludeFromSemantics: true,
                  'assets/images/wallet_rider_3d.webp',
                  fit: BoxFit.contain,
                  cacheHeight: 400,
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  context.l10n.addFundsToWallet,
                  textAlign: TextAlign.center,
                  style: _style(15, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  context.l10n.topUpForRides,
                  textAlign: TextAlign.center,
                  style: _style(12, color: _muted),
                ),
              ),
              const SizedBox(height: 16),
              if (_failed)
                MoveraEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: context.l10n.walletLoadFailed,
                  message: context.l10n.walletLoadFailedBody,
                  actionLabel: context.l10n.retry,
                  onAction: _restore,
                  compact: true,
                )
              else if (_loading)
                MoveraEmptyState(
                  icon: Icons.hourglass_empty_rounded,
                  title: context.l10n.loadingWallet,
                  message: context.l10n.checkingBalance,
                  compact: true,
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF11181D), Color(0xFF2D5878)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF11181D).withValues(alpha: 0.28),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'MOVERA',
                            style: _style(
                              11,
                              weight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.7),
                            ).copyWith(letterSpacing: 2.2),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.contactless_rounded,
                            color: Colors.white.withValues(alpha: 0.86),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _currencyChips(),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.availableBalance,
                        style: _style(
                          12,
                          weight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        // rider-r5-14: exact, as Pay With shows it and as
                        // Select Ride compares it; rounding up claimed öre
                        // the wallet does not have.
                        formatMoney(Money.fromLegacyMajor(_balance, _currency)),
                        style: _style(
                          34,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _demoPayments && !_topUpBusy
                              ? _openAddFunds
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: _ink,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _topUpBusy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _demoPayments
                                      ? context.l10n.addFundsDemo
                                      : context.l10n.addFundsUnavailable,
                                  style: _style(14, weight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Semantics(
                enabled: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.confirmation_number_outlined,
                        color: _muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.vouchersUnavailable,
                          style: _style(14, color: _muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _demoPayments
                    ? context.l10n.demoTopUpsSimulated
                    : context.l10n.topUpsUnavailable,
                style: _style(12.5, color: _muted, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    this.embedded = false,
    this.refreshToken = 0,
    this.flags = FeatureFlags.current,
    this.wallet,
  });

  final bool embedded;

  /// The wallet to read and save payment settings with; the app's without.
  final WalletController? wallet;

  /// A new value re-reads the wallet balance (FLOW-17).
  final int refreshToken;
  final FeatureFlags flags;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const Color _ink = Color(0xFF171C1F);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _surface = Color(0xFFF4F5F4);
  static const Color _line = Color(0xFFE6E8E7);
  static const Color _accent = Color(0xFF356879);
  late final WalletController _homeWallet =
      widget.wallet ?? AppScope.instance.walletController;
  final SavedCardsController _cards = AppScope.instance.savedCards;

  /// Q7/Q8: the rider's current zone decides which wallet balance and
  /// which payment methods (its config's) are listed.
  String _currency = Money.defaultCurrency;
  List<String> _zoneMethods = ZoneDefaults.paymentMethods;
  WalletController get _wallet => _homeWallet.forCurrency(_currency);
  bool _offers(String method) => _zoneMethods.contains(method);

  Future<void> _loadZone() async {
    final zone = await currentRiderZone();
    List<String>? methods;
    try {
      methods = (await AppScope.instance.riderConfig.forZone(
        zone.id,
      )).paymentMethods;
    } catch (_) {
      methods = null;
    }
    if (!mounted) return;
    setState(() {
      _currency = zone.currency;
      if (methods != null) _zoneMethods = methods;
    });
    await _reloadBalance();
  }

  bool _businessProfile = false;
  String _selectedMethod = 'cash';
  double _balance = 0;

  /// rider-fixrev3-5: bumped by every method or profile choice made on
  /// this screen, so a settings load that answers after a tap (the server
  /// default can take seconds in release) does not put the older value back.
  int _methodEdits = 0;
  int _profileEdits = 0;

  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  List<Map<String, String>> _extraMethods = [];

  @override
  void initState() {
    super.initState();
    _cards.addListener(_cardsChanged);
    _restorePaymentSettings();
    _loadCards();
    _loadZone();
  }

  @override
  void didUpdateWidget(covariant WalletScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reloadBalance();
  }

  Future<void> _reloadBalance() async {
    final currency = _currency;
    final balance = await _wallet.loadBalance();
    if (mounted && currency == _currency) setState(() => _balance = balance);
  }

  @override
  void dispose() {
    _cards.removeListener(_cardsChanged);
    super.dispose();
  }

  void _cardsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCards() async {
    try {
      await _cards.load();
    } catch (error) {
      AppLog.warning('wallet.cards_load_failed', extra: {'error': '$error'});
    }
  }

  TextStyle _style(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
    double? height,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  Future<void> _restorePaymentSettings() async {
    final currency = _currency;
    final methodEdits = _methodEdits;
    final profileEdits = _profileEdits;
    final saved = await _wallet.loadPayments();
    final balance = await _wallet.loadBalance();
    if (!mounted) return;
    setState(() {
      if (currency == _currency) _balance = balance;
      if (methodEdits == _methodEdits) _selectedMethod = saved.defaultMethod;
      if (profileEdits == _profileEdits) _businessProfile = saved.business;
      _extraMethods = saved.extraMethods;
    });
  }

  Future<void> _savePaymentSettings() async {
    await _wallet.savePayments(
      WalletPaymentSettings(
        defaultMethod: _selectedMethod,
        business: _businessProfile,
        extraMethods: _extraMethods,
      ),
    );
  }

  void _selectMethod(String id) {
    _methodEdits++;
    setState(() => _selectedMethod = id);
    _savePaymentSettings();
  }

  void _selectProfile(bool business) {
    _profileEdits++;
    setState(() => _businessProfile = business);
    _wallet.saveBusiness(business);
  }

  Future<void> _openAddPaymentMethod() async {
    final card = await AddCardPage.open(context, cards: _cards);
    if (card == null || !mounted) return;
    _selectMethod(card.methodBrand);
  }

  /// "Remove this card?" then removes it; the default falls back to Pay in
  /// car when the removed card was the default.
  Future<void> _confirmRemoveCard(SavedCard card) async {
    final confirmed = await MoveraSheet.show<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _brandMark(card.methodBrand)),
                const SizedBox(height: 14),
                Text(
                  context.l10n.removeCardQ(card.displayName),
                  textAlign: TextAlign.center,
                  style: _style(18, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.addAgainAnyTime,
                  textAlign: TextAlign.center,
                  style: _style(13, weight: FontWeight.w400, color: _muted),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('wallet-remove-card-confirm'),
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF11181D),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      context.l10n.removeCard,
                      style: _style(
                        15,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text(
                    context.l10n.keepCard,
                    style: _style(15, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _cards.remove(card.id);
    if (!mounted) return;
    if (_selectedMethod == card.methodBrand) _selectMethod('cash');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.embedded) _header(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.howToPay,
                      style: _style(27, weight: FontWeight.w700, height: 1.18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.chooseDefaultMethod,
                      style: _style(
                        11.5,
                        weight: FontWeight.w400,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 22),
                    // FLOW-11: hidden until Business does something.
                    if (widget.flags.businessProfile) ...[
                      _profileSelector(),
                      const SizedBox(height: 25),
                    ] else
                      const SizedBox(height: 3),
                    _sectionLabel(context.l10n.paymentMethodsUpper),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _line),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.035),
                            blurRadius: 22,
                            offset: const Offset(0, 9),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Offered only when there is money in the wallet.
                          if (_balance > 0) ...[
                            _paymentTile(
                              id: 'wallet',
                              title: context.l10n.moveraWallet,
                              detail: context.l10n.payFromBalance,
                              brand: 'wallet',
                            ),
                            const Divider(
                              height: 1,
                              indent: 62,
                              endIndent: 16,
                              color: _line,
                            ),
                          ],
                          if (!_isAndroid && _offers('apple_pay'))
                            _paymentTile(
                              id: 'apple',
                              title: 'Apple Pay',
                              detail: context.l10n.paysWhenSearchStarts,
                              brand: 'apple',
                            ),
                          const Divider(
                            height: 1,
                            indent: 62,
                            endIndent: 16,
                            color: _line,
                          ),
                          if (!_isIos && _offers('google_pay'))
                            _paymentTile(
                              id: 'google',
                              title: 'Google Pay',
                              detail: context.l10n.paysWhenSearchStarts,
                              brand: 'google',
                            ),
                          const Divider(
                            height: 1,
                            indent: 62,
                            endIndent: 16,
                            color: _line,
                          ),
                          if (_offers('cash'))
                            _paymentTile(
                              id: 'cash',
                              title: context.l10n.payCash,
                              detail: context.l10n.payDriverCash,
                              brand: 'cash',
                            ),
                          for (final method in _extraMethods) ...[
                            const Divider(
                              height: 1,
                              indent: 62,
                              endIndent: 16,
                              color: _line,
                            ),
                            _paymentTile(
                              id: method['id']!,
                              title: method['title']!,
                              detail: method['detail']!,
                              brand: method['id']!,
                            ),
                          ],
                          for (final card
                              in _offers('card')
                                  ? _cards.list()
                                  : const <SavedCard>[]) ...[
                            const Divider(
                              height: 1,
                              indent: 62,
                              endIndent: 16,
                              color: _line,
                            ),
                            _paymentTile(
                              id: card.methodBrand,
                              title: card.displayName,
                              detail: context.l10n.cardExpires(
                                card.expiryLabel,
                              ),
                              brand: card.methodBrand,
                              onRemove: () => _confirmRemoveCard(card),
                            ),
                          ],
                          if (CardEntryPolicy.enabled && _offers('card')) ...[
                            const Divider(
                              height: 1,
                              indent: 62,
                              endIndent: 16,
                              color: _line,
                            ),
                            _actionTile(
                              icon: Icons.add_rounded,
                              title: context.l10n.addCard,
                              onTap: _openAddPaymentMethod,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    _sectionLabel(context.l10n.vouchersUpper),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Semantics(
                        enabled: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 15,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.confirmation_number_outlined,
                                color: _muted,
                                size: 21,
                              ),
                              const SizedBox(width: 17),
                              Expanded(
                                child: Text(
                                  context.l10n.vouchersUnavailable,
                                  style: _style(12, color: _muted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          color: _muted,
                          size: 15,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            context.l10n.paymentPrefsProtected,
                            style: _style(
                              9.5,
                              weight: FontWeight.w400,
                              color: _muted,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: context.l10n.back,
            child: Material(
              color: _surface,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(Icons.arrow_back_rounded, color: _ink, size: 22),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              context.l10n.navPayment,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _style(13, weight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 42),
        ],
      ),
    );
  }

  Widget _profileSelector() {
    // UI-4: the 4 px frame is part of each option's target (46 px tall), not
    // padding around the 38 px options.
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _profileOption(
            label: context.l10n.profilePersonal,
            icon: Icons.person_outline_rounded,
            selected: !_businessProfile,
            onTap: () => _selectProfile(false),
            frame: const EdgeInsets.fromLTRB(4, 4, 0, 4),
          ),
          _profileOption(
            label: context.l10n.profileBusiness,
            icon: Icons.business_center_outlined,
            selected: _businessProfile,
            onTap: () => _selectProfile(true),
            frame: const EdgeInsets.fromLTRB(0, 4, 4, 4),
          ),
        ],
      ),
    );
  }

  Widget _profileOption({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    required EdgeInsets frame,
  }) {
    return Expanded(
      child: MoveraHitArea(
        label: label,
        selected: selected,
        onTap: onTap,
        child: Padding(
          padding: frame,
          child: Material(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              onTap: onTap,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.055),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: selected ? _ink : _muted, size: 16),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _style(
                          11.5,
                          weight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? _ink : _muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: _style(
        10,
        weight: FontWeight.w600,
        color: _muted,
      ).copyWith(letterSpacing: 1.25),
    );
  }

  Widget _paymentTile({
    required String id,
    required String title,
    required String detail,
    required String brand,
    VoidCallback? onRemove,
  }) {
    final selected = _selectedMethod == id;
    return Material(
      key: ValueKey('wallet-method-$id'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectMethod(id),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, onRemove == null ? 14 : 6, 12),
          child: Row(
            children: [
              _brandMark(brand),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(12.5, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected ? context.l10n.defaultForRides : detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _style(
                        9.3,
                        weight: FontWeight.w400,
                        color: selected ? _accent : _muted,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? _ink : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? _ink : _line,
                    width: 1.4,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 15,
                      )
                    : null,
              ),
              if (onRemove != null)
                IconButton(
                  key: ValueKey('wallet-remove-$id'),
                  tooltip: context.l10n.removeCard,
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: _muted,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandMark(String brand) {
    Widget logo;
    Color background = Colors.white;

    final savedCard = _cards.byMethodBrand(brand);
    if (savedCard != null) {
      logo = Image.asset(
        excludeFromSemantics: true,
        savedCard.brand == 'mastercard' ? AppAssets.mastercard : AppAssets.visa,
        fit: BoxFit.contain,
      );
    } else if (brand == 'apple') {
      logo = SvgPicture.asset(
        'assets/images/apple_pay_brand.svg',
        fit: BoxFit.contain,
      );
    } else if (brand == 'google') {
      logo = Image.asset(
        excludeFromSemantics: true,
        'assets/images/google_pay_brand.png',
        fit: BoxFit.contain,
      );
    } else if (brand == 'cards') {
      logo = Row(
        children: [
          Expanded(
            child: Image.asset(
              excludeFromSemantics: true,
              AppAssets.visa,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Image.asset(
              excludeFromSemantics: true,
              AppAssets.mastercard,
              fit: BoxFit.contain,
            ),
          ),
        ],
      );
    } else if (brand == 'wallet' || brand.startsWith('wallet')) {
      background = const Color(0xFF11181D);
      logo = const Icon(
        Icons.account_balance_wallet_rounded,
        color: Colors.white,
        size: 20,
      );
    } else if (brand == 'cash') {
      background = const Color(0xFFEEF6F0);
      logo = const Icon(
        Icons.payments_outlined,
        color: Color(0xFF1F7A4D),
        size: 20,
      );
    } else {
      logo = Image.asset(
        excludeFromSemantics: true,
        AppAssets.mastercard,
        fit: BoxFit.contain,
      );
    }

    return Container(
      width: 42,
      height: 38,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: background == Colors.white ? _line : background,
        ),
      ),
      child: brand == 'google'
          ? Transform.scale(scale: 1.18, child: logo)
          : logo,
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: _ink, size: 21),
              const SizedBox(width: 17),
              Expanded(
                child: Text(title, style: _style(12, weight: FontWeight.w600)),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 21),
            ],
          ),
        ),
      ),
    );
  }
}
