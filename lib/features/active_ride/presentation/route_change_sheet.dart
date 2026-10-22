import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// True for "Cash": the price is only shown, nothing is charged now.
bool isCashPayment(String paymentMethod) {
  final m = paymentMethod.trim().toLowerCase();
  // Round 4: "Cash" may reach here in the app language too.
  return m == 'cash' || m.contains('pay in car') || L10n.isCashLabel(m);
}

/// Where a refund goes when the new route is cheaper.
enum RefundDestination { wallet, originalMethod }

/// What the rider decided on the route change sheet.
class RouteChangeDecision {
  const RouteChangeDecision({required this.confirmed, this.refundTo});
  final bool confirmed;

  /// Set only for a confirmed refund on a non-cash method.
  final RefundDestination? refundTo;

  static const declined = RouteChangeDecision(confirmed: false);
}

/// "New route, new price": the rider confirms a priced route change. For a
/// card, Apple Pay or wallet a second step confirms the payment update; a
/// refund also asks where the money should go.
class RouteChangeSheet extends StatefulWidget {
  const RouteChangeSheet({
    super.key,
    required this.quote,
    required this.paymentMethod,
    this.paymentMethodId,
  });

  final RouteChangeQuote quote;
  final String paymentMethod;

  /// ARCH-9: the booked method's id; decides "Cash" when known.
  final String? paymentMethodId;

  static Future<RouteChangeDecision> confirm(
    BuildContext context, {
    required RouteChangeQuote quote,
    required String paymentMethod,
    String? paymentMethodId,
  }) async {
    final result = await MoveraSheet.show<RouteChangeDecision>(
      context: context,
      builder: (_) => RouteChangeSheet(
        quote: quote,
        paymentMethod: paymentMethod,
        paymentMethodId: paymentMethodId,
      ),
    );
    return result ?? RouteChangeDecision.declined;
  }

  @override
  State<RouteChangeSheet> createState() => _RouteChangeSheetState();
}

class _RouteChangeSheetState extends State<RouteChangeSheet> {
  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _accent = Color(0xFF2D5878);

  bool _paymentStep = false;

  /// Q8: the refund goes to the wallet balance of the trip's own currency
  /// (one per currency, no conversion), where this build has a wallet.
  late final bool _walletRefund = AppScope.instance.walletController
      .forCurrency(quote.currency)
      .available;
  late RefundDestination _refundTo = _walletRefund
      ? RefundDestination.wallet
      : RefundDestination.originalMethod;

  RouteChangeQuote get quote => widget.quote;
  String get paymentMethod => widget.paymentMethod;
  bool get _cash => isCashPayment(widget.paymentMethodId ?? paymentMethod);
  double get _diff => quote.differenceKr;

  /// [value] whole units of the trip's currency, as the fare is shown.
  String _kr(double value) => formatMajor(value, quote.currency);

  void _confirmRoute() {
    if (_cash || !quote.changesPrice) {
      Navigator.pop(context, const RouteChangeDecision(confirmed: true));
      return;
    }
    setState(() => _paymentStep = true);
  }

  void _confirmPayment() {
    Navigator.pop(
      context,
      RouteChangeDecision(
        confirmed: true,
        refundTo: _diff < 0 ? _refundTo : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + inset),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _paymentStep ? _payment(context) : _route(context),
      ),
    );
  }

  Widget _route(BuildContext context) {
    final diff = _diff;
    final String priceNote;
    if (!quote.changesPrice) {
      priceNote = context.l10n.samePrice;
    } else if (_cash) {
      priceNote = diff > 0
          ? context.l10n.moreCash(_kr(diff))
          : context.l10n.lessCash(_kr(-diff));
    } else if (diff > 0) {
      // rider-u231: the method's name in the app language.
      priceNote =
          context.l10n.moreCharged(_kr(diff), paymentLabelFor(paymentMethod));
    } else {
      priceNote =
          context.l10n.lessReturned(_kr(-diff), paymentLabelFor(paymentMethod));
    }
    return _step(
      key: const ValueKey('route-change-step-route'),
      body: [
        Text(
          context.l10n.newRoute,
          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: _ink),
        ),
        const SizedBox(height: 14),
        _row(Icons.radio_button_checked, const Color(0xFF079A60), quote.pickupAddress),
        for (var i = 0; i < quote.stops.length; i++)
          _row(Icons.circle_outlined, _ink, quote.stops[i].address, label: context.l10n.stopNumber('${i + 1}')),
        _row(Icons.square, const Color(0xFF1769E8), quote.destinationAddress),
      ],
      // The new price stays next to Confirm; only the route list scrolls.
      actions: [
        Container(
          key: const ValueKey('route-change-price'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6FB),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.newPrice,
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: _muted),
                    ),
                    const SizedBox(height: 2),
                    Text(priceNote, style: GoogleFonts.poppins(fontSize: 12.5, color: _muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _kr(quote.newPriceKr),
                    style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: _ink),
                  ),
                  if (quote.changesPrice)
                    Text(
                      _kr(quote.oldPriceKr),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: _muted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _primary(
          key: const ValueKey('route-change-confirm'),
          label: _cash || !quote.changesPrice ? context.l10n.confirmChange : context.l10n.confirmNextPayment,
          onPressed: _confirmRoute,
        ),
        const SizedBox(height: 8),
        _secondary(
          context.l10n.keepCurrentRoute,
          () => Navigator.pop(context, RouteChangeDecision.declined),
        ),
      ],
    );
  }

  Widget _payment(BuildContext context) {
    final diff = _diff;
    final more = diff > 0;
    return _step(
      key: const ValueKey('route-change-step-payment'),
      body: [
        Text(
          more ? context.l10n.confirmPayment : context.l10n.chooseRefund,
          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: _ink),
        ),
        const SizedBox(height: 6),
        Text(
          more
              ? context.l10n.routeChargedNow
              : context.l10n.routeCostsLess,
          style: GoogleFonts.poppins(fontSize: 13.5, color: _muted),
        ),
        const SizedBox(height: 16),
        Container(
          key: const ValueKey('route-change-payment'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6FB),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _kv(context.l10n.paymentMethod, paymentMethod),
              const SizedBox(height: 8),
              _kv(context.l10n.bookedPrice, _kr(quote.oldPriceKr)),
              const SizedBox(height: 8),
              _kv(context.l10n.newPrice, _kr(quote.newPriceKr)),
              const Divider(height: 20),
              _kv(
                more ? context.l10n.chargedNow : context.l10n.refundAmount,
                '${more ? '+' : ''}${_kr(diff.abs())}',
                bold: true,
              ),
            ],
          ),
        ),
        if (!more) ...[
          if (_walletRefund) ...[
            const SizedBox(height: 14),
            _refundOption(
              RefundDestination.wallet,
              key: const ValueKey('refund-to-wallet'),
              title: context.l10n.moveraWallet,
              subtitle:
                  context.l10n.refundWalletBody,
              icon: Icons.account_balance_wallet_outlined,
            ),
          ],
          const SizedBox(height: 8),
          _refundOption(
            RefundDestination.originalMethod,
            key: const ValueKey('refund-to-original'),
            title: paymentMethod,
            subtitle:
                context.l10n.refundOriginalBody,
            icon: Icons.credit_card_outlined,
          ),
        ],
      ],
      actions: [
        const SizedBox(height: 18),
        _primary(
          key: const ValueKey('route-change-pay'),
          label: more
              ? context.l10n.confirmAndPay(_kr(diff))
              : _refundTo == RefundDestination.wallet
              ? context.l10n.confirmRefundWallet
              : context.l10n.confirmRefundTo(paymentMethod),
          onPressed: _confirmPayment,
        ),
        const SizedBox(height: 8),
        _secondary(context.l10n.back, () => setState(() => _paymentStep = false)),
      ],
    );
  }

  /// UI-05: the step's content scrolls when the sheet is short (two stops
  /// at large text, a landscape phone), while its buttons stay in reach.
  Widget _step({
    required Key key,
    required List<Widget> body,
    required List<Widget> actions,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: body,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...actions,
      ],
    );
  }

  Widget _refundOption(
    RefundDestination value, {
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _refundTo == value;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _refundTo = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _ink : const Color(0xFFE2E6EA),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: _ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w600, color: _ink),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: GoogleFonts.poppins(fontSize: 12.5, color: _muted)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 22,
                color: selected ? _ink : const Color(0xFFC3C9CE),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _primary({required Key key, required String label, required VoidCallback onPressed}) {
    // A minimum height, not a fixed one: a long label at large text wraps
    // inside the button instead of being clipped (UI-05).
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: double.infinity,
        minHeight: 54,
      ),
      child: FilledButton(
        key: key,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF11181D),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
        ),
      ),
    );
  }

  Widget _secondary(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: _accent),
        child: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
      ),
    );
  }

  Widget _kv(String left, String right, {bool bold = false}) {
    // UI-05: the value keeps its place on the right but may take at most
    // 60% of the row, so a long method name wraps instead of overflowing.
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          Expanded(
            child: Text(
              left,
              style: GoogleFonts.poppins(fontSize: 14, color: bold ? _ink : _muted, fontWeight: bold ? FontWeight.w600 : FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
            child: Text(
              right,
              textAlign: TextAlign.end,
              style: GoogleFonts.poppins(fontSize: bold ? 16 : 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: _ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, Color color, String address, {String? label}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 22, child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
