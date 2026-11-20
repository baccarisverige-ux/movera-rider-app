import 'package:flutter/material.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// R6: the rider's words for a receipt line code
/// (contract.json#fareLines.rider). A code this app does not know yet is
/// still shown, as "Other", so no amount of the receipt is ever hidden.
String receiptFareLineLabel(AppLocalizations l10n, String code) =>
    switch (code) {
      'base' => l10n.receiptLineBase,
      'distance' => l10n.receiptLineDistance,
      'time' => l10n.receiptLineTime,
      'fixed_route' => l10n.receiptLineFixedRoute,
      'surge' => l10n.receiptLineSurge,
      'minimum_adjust' => l10n.receiptLineMinimumAdjust,
      'maximum_adjust' => l10n.receiptLineMaximumAdjust,
      'waiting' => l10n.receiptLineWaiting,
      'stops' => l10n.receiptLineStops,
      'stop_waiting' => l10n.receiptLineStopWaiting,
      'extras' => l10n.receiptLineExtras,
      'airport' => l10n.receiptLineAirport,
      'reservation_fee' => l10n.receiptLineReservationFee,
      'app_fee' => l10n.receiptLineAppFee,
      'pickup_fee' => l10n.receiptLinePickupFee,
      'rounding' => l10n.receiptLineRounding,
      'discount' => l10n.receiptLineDiscount,
      'cancel_fee' => l10n.receiptLineCancelFee,
      'rider_raise' => l10n.receiptLineRiderRaise,
      'outstanding_fee' => l10n.receiptDebtIncluded,
      _ => l10n.receiptLineOther,
    };

/// The receipt's extra lines under the trip details.
class ServerReceiptLines extends StatefulWidget {
  const ServerReceiptLines({
    super.key,
    required this.rideId,
    this.loader,
    this.showEndedEarly = true,
    this.showTotal = false,
  });

  /// History (live sweep M-11): the receipt's total comes first, under a
  /// "Receipt" heading.
  final bool showTotal;

  final String rideId;
  final Future<ServerReceipt?> Function(String rideId)? loader;

  /// False when the details already say the trip ended early.
  final bool showEndedEarly;

  @override
  State<ServerReceiptLines> createState() => _ServerReceiptLinesState();
}

class _ServerReceiptLinesState extends State<ServerReceiptLines> {
  ServerReceipt? _receipt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final receipt = await (widget.loader ?? ServerReceipt.load)(widget.rideId);
    if (!mounted || receipt == null) return;
    setState(() => _receipt = receipt);
  }

  Widget _line(String label, String value, {Key? key}) => Padding(
    key: key,
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6F7B82)),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  /// A line's amount as the server sent it; a minus line with a real
  /// minus sign, as the refund line.
  static String _amount(Money amount) => amount.amountMinor < 0
      ? '−${formatMoney(Money(-amount.amountMinor, amount.currency))}'
      : formatMoney(amount);

  /// R6: the server's receipt lines, one row each, in the server's order.
  List<Widget> _fareLines(AppLocalizations l10n, ServerReceipt receipt) {
    final seen = <String, int>{};
    return [
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          l10n.receiptLinesHeading,
          key: const ValueKey('receipt-lines-heading'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      for (final line in receipt.fareLines)
        _line(
          receiptFareLineLabel(l10n, line.code),
          _amount(line.amount),
          key: ValueKey(() {
            final n = seen.update(line.code, (n) => n + 1, ifAbsent: () => 0);
            return n == 0
                ? 'receipt-line-${line.code}'
                : 'receipt-line-${line.code}-$n';
          }()),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    if (receipt == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    // The earlier unpaid fee is one of the lines when the server lists it.
    final debtIsALine = receipt.fareLines.any(
      (line) => line.code == 'outstanding_fee',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTotal) ...[
          Text(
            l10n.receiptHeading,
            key: const ValueKey('receipt-heading'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          if (receipt.total case final total?)
            _line(
              l10n.total,
              formatMoney(total),
              key: const ValueKey('receipt-total'),
            ),
        ],
        if (receipt.endedEarly && widget.showEndedEarly)
          _line(
            l10n.endedEarly,
            receipt.endedBy == 'driver'
                ? l10n.receiptDriverEnded
                : l10n.receiptRiderEnded,
            key: const ValueKey('receipt-ended-early'),
          )
        else if (receipt.endedEarly)
          _line(
            l10n.endedEarlyReason,
            receipt.endedBy == 'driver'
                ? l10n.receiptDriverEnded
                : l10n.receiptRiderEnded,
            key: const ValueKey('receipt-ended-early'),
          ),
        if (receipt.fareLines.isNotEmpty) ..._fareLines(l10n, receipt),
        if (receipt.debtIncluded case final debt? when !debtIsALine)
          _line(
            l10n.receiptDebtIncluded,
            formatMoney(debt),
            key: const ValueKey('receipt-debt'),
          ),
        // Fix job 0 (owner A2-2, contract 0.18.29 outstandingFee.receiptText):
        // the owed fee was added by itself to this trip; say so in words.
        if (receipt.debtIncluded != null || debtIsALine)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.receiptDebtIncludedNote,
              key: const ValueKey('receipt-debt-note'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF6F7B82)),
            ),
          ),
        if (receipt.tip case final tip?)
          _line(
            l10n.receiptTip,
            formatMoney(tip),
            key: const ValueKey('receipt-tip'),
          ),
        if (receipt.refunded case final refunded?)
          _line(
            l10n.receiptRefunded,
            '−${formatMoney(refunded)}',
            key: const ValueKey('receipt-refunded'),
          ),
      ],
    );
  }
}
