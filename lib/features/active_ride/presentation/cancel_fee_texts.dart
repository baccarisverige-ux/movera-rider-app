import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// What the rider reads after a cancel or a no-show (contract v0.18.7
/// `pickupWaiting.feeAmountsShown.texts`): "Cancellation fee {amount}",
/// "No-show fee {amount}" or "No fee", from the projection's
/// `cancellation.fee` + `feeKind`. Null when the server has not said.
String? riderCancelFeeText(RiderCancelOutcomeFee? outcome) {
  if (outcome == null) return null;
  final fee = outcome.fee;
  if (fee == null || !fee.isPositive) return L10n.current.cancelledNoFee;
  final amount = formatMoney(fee);
  return outcome.kind == CancelFeeKind.noShow
      ? L10n.current.cancelledNoShowFee(amount)
      : L10n.current.cancelledFeeCharged(amount);
}
