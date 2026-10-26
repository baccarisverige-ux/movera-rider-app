import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// What to tell the rider after a top-up, or null when it went through.
///
/// Every message says whether money was taken. A failed top-up used to show
/// nothing at all.
String? topUpMessage(TopUpOutcome outcome) {
  switch (outcome) {
    case TopUpCredited():
      return null;
    case TopUpUnconfirmed():
      return L10n.current.topUpUnconfirmed;
    case TopUpNotCharged(declined: true):
      return L10n.current.topUpDeclined;
    case TopUpNotCharged(:final error):
      final kind = error == null
          ? RiderErrorKind.unknown
          : riderErrorKind(error);
      switch (kind) {
        case RiderErrorKind.offline:
          return L10n.current.topUpOffline;
        case RiderErrorKind.rateLimited:
          final wait = error == null ? null : riderRetryWait(error);
          return L10n.current.topUpRateLimited(
            wait == null
                ? L10n.current.inAMoment
                : L10n.current.inDuration(wait),
          );
        case RiderErrorKind.serverTrouble:
          return L10n.current.topUpServerTrouble;
        case RiderErrorKind.refused:
        case RiderErrorKind.unknown:
          return L10n.current.topUpFailed;
      }
  }
}
