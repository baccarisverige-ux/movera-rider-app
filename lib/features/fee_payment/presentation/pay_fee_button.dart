import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/fee_payment/application/fee_card_payer.dart';
import 'package:movera_rider/features/fee_payment/data/stripe_fee_payment_sheet.dart';
import 'package:movera_rider/features/fee_payment/domain/fees_payable_by_card.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// v0.18.136 stripeFees (DRAFT): "Pay 65,00 kr now" for one owed fee, the
/// server's amount. The paid status is the server's (read back after the sheet).
class PayFeeButton extends StatefulWidget {
  const PayFeeButton({super.key, required this.fee, this.payer});
  final FeePayable fee;
  final FeeCardPayer? payer;

  @override
  State<PayFeeButton> createState() => _PayFeeButtonState();
}

class _PayFeeButtonState extends State<PayFeeButton> {
  bool _busy = false;

  Future<void> _pay() async {
    setState(() => _busy = true);
    final payer =
        widget.payer ??
        FeeCardPayer(
          api: AppScope.instance.api,
          sheet: const StripeFeePaymentSheet(),
        );
    final outcome = await payer.pay(widget.fee.tripId);
    if (!mounted) return;
    setState(() => _busy = false);
    final l10n = context.l10n;
    final text = switch (outcome) {
      FeePayOutcome.paid => l10n.feePaidByCard,
      FeePayOutcome.checking => l10n.feePaymentChecking,
      FeePayOutcome.failed => l10n.feePaymentFailed,
      FeePayOutcome.unavailable => l10n.feePaymentUnavailable,
      FeePayOutcome.closed => null,
    };
    if (text == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('fee-pay-outcome'),
          content: Text(text),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) => FilledButton(
    key: ValueKey('fee-pay-${widget.fee.tripId}'),
    onPressed: _busy ? null : _pay,
    child: Text(context.l10n.feePayByCard(formatMoney(widget.fee.amount))),
  );
}

/// v0.18.136 stripeFees (DRAFT): after a late cancel, the fee notice offers
/// "Pay … now" for the newest fee the server says is payable by card (the
/// server's amount; nothing when the country switch is off).
Future<void> offerFeePayAfterCancel(
  ScaffoldMessengerState messenger,
  String text, {
  FeeCardPayer? payer,
}) async {
  final pay =
      payer ??
      FeeCardPayer(
        api: AppScope.instance.api,
        sheet: const StripeFeePaymentSheet(),
      );
  await pay.refresh();
  final items = FeesPayableByCard.current.value.items;
  if (items.isEmpty || !messenger.mounted) return;
  final fee = items.last;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('cancel-fee-outcome'),
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          key: const ValueKey('cancel-fee-pay'),
          label: L10n.current.feePayByCard(formatMoney(fee.amount)),
          onPressed: () async {
            final outcome = await pay.pay(fee.tripId);
            if (!messenger.mounted) return;
            final done = switch (outcome) {
              FeePayOutcome.paid => L10n.current.feePaidByCard,
              FeePayOutcome.checking => L10n.current.feePaymentChecking,
              FeePayOutcome.failed => L10n.current.feePaymentFailed,
              FeePayOutcome.unavailable => L10n.current.feePaymentUnavailable,
              FeePayOutcome.closed => null,
            };
            if (done != null)
              messenger.showSnackBar(
                SnackBar(
                  key: const ValueKey('fee-pay-outcome'),
                  content: Text(done),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          },
        ),
      ),
    );
}
