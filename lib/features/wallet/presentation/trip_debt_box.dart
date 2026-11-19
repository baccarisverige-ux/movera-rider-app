import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// Debt line M2 (owner 2026-11-19 "Yes, build M2 + M3"; Q-M1 "as its own
/// line"): under the booked payment line of a ride, the rider's unpaid fee
/// from an earlier trip and what there is to pay with it:
///
///     + 35,00 kr obetald avgift från tidigare resa
///     Att betala                          250,00 kr
///
/// Display only. The payment line above it is not changed, and no amount
/// is changed anywhere: the server reads the debt when the trip is paid
/// (contract `debtModel.readAtPayment`).
///
/// Nothing is shown (the screen is exactly as before) when:
/// * the rider owes nothing in the trip's [currency] (a debt in another
///   currency is never added to this trip);
/// * the server has not answered a debt read made by this box (the debt
///   kept in the app is read once per sign-in and may be old);
/// * the wallet pays a part of the ride ([walletMinor] > 0: a wallet with
///   money has no debt in that currency).
class TripDebtBox extends StatefulWidget {
  const TripDebtBox({
    super.key,
    required this.priceKr,
    required this.currency,
    this.walletMinor = 0,
    this.stage,
    this.topGap = 10,
  });

  /// The price on the payment line above, in major units of [currency].
  final double priceKr;

  /// ISO-4217 code of the trip.
  final String currency;

  /// The part of the price booked to the Movera Wallet, in minor units.
  final int walletMinor;

  /// The debt is read again whenever this changes (the ride's stage), so a
  /// fee an admin removed during the ride goes from the screen.
  final Object? stage;

  /// Space above the box; part of the box, so no box leaves no gap.
  final double topGap;

  @override
  State<TripDebtBox> createState() => _TripDebtBoxState();
}

class _TripDebtBoxState extends State<TripDebtBox> {
  /// True once the server answered a read made by this box.
  bool _known = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(TripDebtBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage) _read();
  }

  Future<void> _read() async {
    final answered = await RiderOutstanding.refresh();
    if (!mounted || !answered || _known) return;
    setState(() => _known = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_known || widget.walletMinor > 0) return const SizedBox.shrink();
    return ValueListenableBuilder<RiderOutstanding>(
      valueListenable: RiderOutstanding.current,
      builder: (context, outstanding, _) {
        final debt = outstanding.inCurrency(widget.currency);
        if (debt == null) return const SizedBox.shrink();
        final price = Money.fromLegacyMajor(widget.priceKr, widget.currency);
        final toPay = Money(
          price.amountMinor + debt.amountMinor,
          widget.currency,
        );
        return Padding(
          padding: EdgeInsets.only(top: widget.topGap),
          child: Container(
            key: const ValueKey<String>('trip-debt-box'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MoveraTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tripDebtLine(formatMoneyFull(debt)),
                  key: const ValueKey<String>('trip-debt-line'),
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: MoveraTokens.muted,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.tripDebtToPay,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: MoveraTokens.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatMoneyFull(toPay),
                      key: const ValueKey<String>('trip-debt-total'),
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: MoveraTokens.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
