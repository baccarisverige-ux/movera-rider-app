import 'package:movera_rider/core/contracts/cancel_preview.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// BQ-M22 (contract v0.18.92 `priceDisplay.cancelPreview.apps`): the cancel
/// sheet's line from the server's preview — the fee now, and from
/// `freeUntil` on `feeAfterFree` with its kind's label. [charged] is true
/// when the line names a fee to pay now.
({String text, bool charged}) cancelPreviewNote(
  CancelPreview preview,
  DateTime now,
) {
  final l = L10n.current;
  final current = preview.at(now);
  if (current.fee.isPositive) {
    final amount = formatMoneyFull(current.fee);
    return (
      text: current.kind == CancelPreviewKind.noShow
          ? l.cancelNoShowCostsNow(amount)
          : l.cancelCostsNow(amount),
      charged: true,
    );
  }
  final until = current.freeUntil;
  if (until == null || !now.isBefore(until)) {
    return (text: l.noFeeToCancel, charged: false);
  }
  // Minutes on the clock until the free cancel ends (time, not money).
  final left = (until.difference(now).inSeconds / 60).ceil();
  return (
    text: left <= 1 ? l.cancelFreeUnderMinute : l.cancelFreeMinutes('$left'),
    charged: false,
  );
}
