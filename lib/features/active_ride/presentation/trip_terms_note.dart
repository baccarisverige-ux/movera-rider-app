import 'package:flutter/material.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The waiting and cancel rules of a trip in words (contract v0.18.7
/// `pickupWaiting.terms.texts`), from the trip's own `terms`, else from the
/// zone's served config. Every number is the server's, in the trip's
/// currency: the app has no waiting prices of its own.
class TripTermsLines {
  const TripTermsLines._(this.lines);

  final List<String> lines;

  static TripTermsLines fromTerms(TripTerms terms) => _build(
    freeWaitMin: terms.freeWaitMin,
    perMin: terms.waitPerMin,
    noShowAfterMin: terms.noShowAfterMin,
    noShowFee: terms.noShowFee,
    cancelAfterArrivedIsNoShow: terms.cancelAfterArrivedIsNoShow,
    maxPickupMoveMeters: terms.maxPickupMoveMeters,
  );

  /// Before a trip exists: the zone's `waiting` (served with the live
  /// pricing) and `booking.maxPickupMoveMeters`.
  static TripTermsLines? fromConfig(
    RiderAppConfig config, {
    String? categoryId,
  }) {
    final waiting = config.waiting;
    if (waiting == null) return null;
    final terms = categoryId == null
        ? waiting
        : waiting.forCategory(categoryId);
    return _build(
      freeWaitMin: terms.freeWaitMin,
      perMin: terms.perMin,
      noShowAfterMin: terms.noShowAfterMin,
      noShowFee: terms.noShowFee,
      cancelAfterArrivedIsNoShow: config.cancelAfterArrivedIsNoShow,
      maxPickupMoveMeters: config.maxPickupMoveMeters,
    );
  }

  static TripTermsLines _build({
    required num freeWaitMin,
    required Money perMin,
    required num noShowAfterMin,
    required Money noShowFee,
    required bool cancelAfterArrivedIsNoShow,
    required int maxPickupMoveMeters,
  }) {
    final l10n = L10n.current;
    String minutes(num value) =>
        value == value.roundToDouble() ? '${value.toInt()}' : '$value';
    return TripTermsLines._([
      l10n.termsFreeWait(minutes(freeWaitMin), formatMoney(perMin)),
      if (noShowFee.isPositive)
        l10n.termsNoShow(minutes(noShowAfterMin), formatMoney(noShowFee)),
      if (cancelAfterArrivedIsNoShow && noShowFee.isPositive)
        l10n.termsCancelAfterArrived,
      l10n.termsPickupMove('$maxPickupMoveMeters'),
    ]);
  }
}

/// The rules behind one row on the Waiting sheet ("Waiting and
/// cancellation"): the sheet itself shows the waiting TIME only (group 6
/// decision 4); the prices open in their own sheet from this row.
class TripTermsNote extends StatelessWidget {
  const TripTermsNote({super.key, required this.lines});

  final TripTermsLines lines;

  static const noteKey = ValueKey('trip-terms-note');
  static const sheetKey = ValueKey('trip-terms-sheet');

  /// Opens the terms as a sheet.
  static Future<void> show(BuildContext context, TripTermsLines lines) {
    return MoveraSheet.show<void>(
      context: context,
      builder: (sheetContext) {
        final inset = MediaQuery.paddingOf(sheetContext).bottom;
        return PointerInterceptor(
          child: Padding(
            key: sheetKey,
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sheetContext.l10n.tripTermsTitle,
                  style: waitingText(18, weight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                for (final line in lines.lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      line,
                      style: waitingText(
                        14,
                        color: MoveraTokens.muted,
                      ).copyWith(height: 1.4),
                    ),
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: MoveraTokens.cta,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(sheetContext.l10n.close),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: noteKey,
        borderRadius: BorderRadius.circular(16),
        onTap: () => show(context, lines),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MoveraTokens.line),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: MoveraTokens.ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.tripTermsTitle,
                  style: waitingText(14, weight: FontWeight.w600),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: MoveraTokens.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
