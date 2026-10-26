import 'package:flutter/material.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/payments/application/card_entry_policy.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/presentation/add_card_page.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/features/promotions/presentation/promotion_details_sheet.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// One payment method shown on [PayWithPage].
class PayWithMethod {
  const PayWithMethod({
    required this.brand,
    required this.name,
    required this.detail,
  });

  final String brand;
  final String name;
  final String detail;
}

/// "Pay with": opens only when the rider taps the payment line. Returns the
/// chosen method's brand, or null when closed without a change.
class PayWithPage extends StatefulWidget {
  const PayWithPage({
    super.key,
    required this.methods,
    required this.selectedBrand,
    required this.walletBalance,
    required this.promotion,
    required this.brandMark,
    this.walletCurrency = Money.defaultCurrency,
    this.walletCoversFare = true,
    this.useWalletFirst = true,
    this.onWalletFirstChanged,
    this.savedCards,
  });

  final List<PayWithMethod> methods;

  /// Whether [walletBalance] pays the whole fare. When it does not, the
  /// wallet row says so and cannot be chosen (rider-74).
  final bool walletCoversFare;

  /// Where "Add payment method" saves the card (defaults to the app's).
  final SavedCardsController? savedCards;

  /// "Use wallet balance first" and what to do when the rider flips it.
  final bool useWalletFirst;
  final ValueChanged<bool>? onWalletFirstChanged;
  final String? selectedBrand;

  /// Shown only when the wallet has money in it.
  final double walletBalance;

  /// Q8: the currency of [walletBalance] (the trip's).
  final String walletCurrency;
  final RiderPromotion? promotion;
  final Widget Function(String brand) brandMark;

  static Future<String?> open(
    BuildContext context, {
    required List<PayWithMethod> methods,
    required String? selectedBrand,
    required double walletBalance,
    required RiderPromotion? promotion,
    required Widget Function(String brand) brandMark,
    String walletCurrency = Money.defaultCurrency,
    bool walletCoversFare = true,
    bool useWalletFirst = true,
    ValueChanged<bool>? onWalletFirstChanged,
    SavedCardsController? savedCards,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PayWithPage(
          methods: methods,
          selectedBrand: selectedBrand,
          walletBalance: walletBalance,
          promotion: promotion,
          brandMark: brandMark,
          walletCurrency: walletCurrency,
          walletCoversFare: walletCoversFare,
          useWalletFirst: useWalletFirst,
          onWalletFirstChanged: onWalletFirstChanged,
          savedCards: savedCards,
        ),
      ),
    );
  }

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _line = Color(0xFFEEF1F2);
  static const Color _accent = Color(0xFF2D5878);

  @override
  State<PayWithPage> createState() => _PayWithPageState();
}

class _PayWithPageState extends State<PayWithPage> {
  late bool _walletFirst = widget.useWalletFirst;

  List<PayWithMethod> get methods => widget.methods;
  String? get selectedBrand => widget.selectedBrand;
  double get walletBalance => widget.walletBalance;
  RiderPromotion? get promotion => widget.promotion;
  Widget Function(String brand) get brandMark => widget.brandMark;

  static const Color _ink = PayWithPage._ink;
  static const Color _muted = PayWithPage._muted;
  static const Color _line = PayWithPage._line;
  static const Color _accent = PayWithPage._accent;

  TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color c = _ink}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c);

  Widget _section(String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: _t(19, w: FontWeight.w700).copyWith(letterSpacing: -0.3),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _row({
    Key? key,
    required Widget leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(
          children: [
            SizedBox(width: 46, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: _t(15.5)),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: _t(12.5, w: FontWeight.w400, c: _muted),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _radio(bool on) => on
      ? const Icon(Icons.check_circle_rounded, color: _accent, size: 26)
      : Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFD2D6D8), width: 2),
          ),
        );

  void _toggleWalletFirst(bool value) {
    setState(() => _walletFirst = value);
    widget.onWalletFirstChanged?.call(value);
  }

  /// Add card; when a card comes back it is the chosen method.
  Future<void> _addCard() async {
    final navigator = Navigator.of(context);
    final card = await AddCardPage.open(context, cards: widget.savedCards);
    if (card == null || !mounted) return;
    navigator.pop(card.methodBrand);
  }

  @override
  Widget build(BuildContext context) {
    final hasSavedCards = methods.any((m) => m.brand.startsWith('card:'));
    // The generic "Card" row only until the rider has saved a card.
    final rideMethods = methods
        .where((m) => m.brand != 'wallet')
        .where((m) => !(hasSavedCards && m.brand == 'cards'))
        .toList();
    final hasWallet =
        walletBalance > 0 && methods.any((m) => m.brand == 'wallet');
    final promo = promotion;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: context.l10n.close,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 26),
                color: _ink,
                padding: EdgeInsets.zero,
              ),
            ),
            Text(
              context.l10n.payWith,
              style: _t(30, w: FontWeight.w700).copyWith(letterSpacing: -0.6),
            ),
            if (hasWallet) ...[
              _section(context.l10n.moveraWallet),
              _row(
                leading: brandMark('wallet'),
                // rider-r4-33: to the öre, as walletCoversFare compares it
                // ("249,60 kr" is too low for 250 kr, never "250 kr").
                title: context.l10n.walletBalance(
                  formatMoney(
                    Money.fromLegacyMajor(walletBalance, widget.walletCurrency),
                  ),
                ),
                subtitle: widget.walletCoversFare
                    ? context.l10n.walletTapToPay
                    : context.l10n.walletTooLowForRide,
                trailing: _radio(selectedBrand == 'wallet'),
                onTap: widget.walletCoversFare
                    ? () => Navigator.of(context).pop('wallet')
                    : null,
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('pay-with-wallet-first'),
                contentPadding: EdgeInsets.zero,
                value: _walletFirst,
                onChanged: _toggleWalletFirst,
                activeTrackColor: const Color(0xFF11181D),
                title: Text(
                  context.l10n.walletFirst,
                  style: _t(15, w: FontWeight.w600),
                ),
                subtitle: Text(
                  context.l10n.walletFirstBody,
                  style: _t(12.5, c: _muted),
                ),
              ),
            ],
            _section(context.l10n.paymentMethods),
            for (final method in rideMethods)
              _row(
                key: ValueKey('pay-with-${method.brand}'),
                leading: brandMark(method.brand),
                title: paymentNameFor(method.brand, method.name),
                subtitle: paymentDetailFor(method.brand, method.detail),
                trailing: _radio(selectedBrand == method.brand),
                onTap: () => Navigator.of(context).pop(method.brand),
              ),
            if (CardEntryPolicy.enabled)
              _row(
                key: const ValueKey('pay-with-add'),
                leading: const Icon(Icons.add_rounded, color: _ink, size: 24),
                title: context.l10n.addPaymentMethod,
                onTap: _addCard,
              ),
            _section(context.l10n.vouchers),
            if (promo != null)
              _row(
                leading: Image.asset(
                  AppAssets.promoCard,
                  width: 40,
                  height: 28,
                ),
                title: promo.title,
                subtitle: context.l10n.ridesLeft(promo.ridesLeft),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: _muted,
                ),
                onTap: () => PromotionDetailsSheet.open(context, promo),
              ),
            _row(
              leading: const Icon(Icons.add_rounded, color: _ink, size: 24),
              title: context.l10n.addVoucherCode,
              subtitle: context.l10n.voucherSoon,
            ),
          ],
        ),
      ),
    );
  }
}
