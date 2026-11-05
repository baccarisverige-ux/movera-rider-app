import 'package:flutter/material.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

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

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    if (receipt == null) return const SizedBox.shrink();
    final l10n = context.l10n;
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
        if (receipt.debtIncluded case final debt?)
          _line(
            l10n.receiptDebtIncluded,
            formatMoney(debt),
            key: const ValueKey('receipt-debt'),
          ),
        // Fix job 0 (owner A2-2, contract 0.18.39 outstandingFee.receiptText):
        // the owed fee was added by itself to this trip; say so in words.
        if (receipt.debtIncluded != null)
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
