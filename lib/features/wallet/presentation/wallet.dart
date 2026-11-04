import 'package:movera_rider/app/config/demo_features.dart';
import 'package:movera_rider/features/payments/presentation/card_brand_label.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/application/card_entry_policy.dart';
import 'package:movera_rider/features/payments/presentation/add_card_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/config/zone_settings.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/features/wallet/application/top_up_message.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/presentation/wallet_balances_line.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/l10n/l10n.dart';

part 'wallet_screen.dart';

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
  bool get _demoPayments => DemoFeatures.on;

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
    // Audit 2026-11-01: one chip per currency (several French zones all
    // pay in EUR: it showed "EUR EUR EUR SEK"), the shown one always in
    // the list, and no chips at all when there is only one currency.
    final codes = <String>{
      for (final zone in RiderZones.all) zone.currency,
      _currency,
    }.toList();
    if (codes.length < 2) return const SizedBox.shrink();
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
                    // Audit M1: the simulated top-up is the demo's only.
                    if (_demoPayments) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.demoTopUpNote,
                        style: _style(
                          12,
                          weight: FontWeight.w400,
                          color: _muted,
                        ),
                      ),
                    ],
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
                  // Page audit round 2: no "top up" heading while top-up is
                  // not available; the button below says why.
                  _demoPayments
                      ? context.l10n.addFundsToWallet
                      : context.l10n.walletHeadingNoTopUp,
                  textAlign: TextAlign.center,
                  style: _style(15, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  _demoPayments
                      ? context.l10n.topUpForRides
                      : context.l10n.walletSubtitleNoTopUp,
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
                      // Fix job 6 (owner Q4 / "Turn it on"): every balance in
                      // its own currency, never a sum (only when 2 or more).
                      WalletBalancesLine(
                        key: ValueKey('balances-$_currency-$_balance'),
                        load: _wallet.loadBalances,
                        style: _style(
                          12,
                          color: Colors.white.withValues(alpha: 0.72),
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
