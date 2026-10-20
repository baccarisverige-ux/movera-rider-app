import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_reason_sheet.dart';
import 'package:movera_rider/features/ride_booking/application/sheet_coordinator.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Confirm cancel, then collect the rider's final decision.
///
/// This helper is intentionally side-effect free until the final reason/skip
/// step returns a cancellation outcome. Closing either sheet or choosing
/// Keep ride must leave matching/active-trip state untouched.
Future<CancelOutcome> showCancelRideSheet(
  BuildContext context, {
  required bool takingLonger,
  CancelPhase phase = CancelPhase.searching,
  Future<void> Function()? onCancelConfirmed,
  String? feeNote,
  bool offerDestinationChange = false,
}) async {
  SheetCoordinator.instance.open(RideSheet.cancel);
  final confirmed = await MoveraSheet.show<bool>(
    context: context,
    swipeDismissible: false,
    barrierDismissible: false,
    builder: (_) => CancelRideSheet(
      takingLonger: takingLonger,
      phase: phase,
      feeNote: feeNote,
    ),
  );
  SheetCoordinator.instance.close(RideSheet.cancel);
  if (confirmed != true || !context.mounted) {
    return const CancelOutcome.keep();
  }

  final outcome = await showCancelReasonSheet(
    context,
    phase: phase,
    offerDestinationChange: offerDestinationChange,
  );
  if (outcome.changeDestination) return outcome;
  if (!outcome.cancelled) return const CancelOutcome.keep();

  // Legacy callback remains supported, but now fires only after the rider
  // completed the final cancellation action.
  if (onCancelConfirmed != null) {
    await onCancelConfirmed();
  }
  return outcome;
}

/// Finding (cancel-first): "Cancel ride?" whose Cancel request commits the
/// cancel at once by running [commit] while the sheet shows progress.
///
/// Returns true once [commit] reported the cancel as committed. Wait for
/// driver, Close, or a driver match arriving before the rider confirmed
/// ([driverMatched] turning true, RIDE-15) close the sheet with false, so the
/// rider never cancels an accepted ride with "still searching" wording. The
/// optional why-sheet is shown by the caller afterwards, as feedback only.
Future<bool> showCancelSearchSheet(
  BuildContext context, {
  required bool takingLonger,
  required Future<bool> Function() commit,
  ValueListenable<bool>? driverMatched,
}) async {
  SheetCoordinator.instance.open(RideSheet.cancel);
  final committed = await MoveraSheet.show<bool>(
    context: context,
    swipeDismissible: false,
    barrierDismissible: false,
    builder: (_) => CancelRideSheet(
      takingLonger: takingLonger,
      phase: CancelPhase.searching,
      onConfirm: commit,
      driverMatched: driverMatched,
    ),
  );
  SheetCoordinator.instance.close(RideSheet.cancel);
  return committed == true;
}

class CancelRideSheet extends StatefulWidget {
  const CancelRideSheet({
    super.key,
    required this.takingLonger,
    this.phase = CancelPhase.searching,
    this.onConfirm,
    this.driverMatched,
    this.feeNote,
  });

  final bool takingLonger;
  final CancelPhase phase;

  /// The cancel fee the rider would pay now, worked out before they
  /// confirm (contract v0.3.0 §5, `rider.cancelFees`). Null: not shown.
  final String? feeNote;

  /// When set, Cancel request runs this (showing progress) and the sheet
  /// closes with its result. Otherwise the sheet just closes with true.
  final Future<bool> Function()? onConfirm;

  /// Closes the sheet (with false) once it turns true, unless a confirmed
  /// cancel is already being sent.
  final ValueListenable<bool>? driverMatched;

  @override
  State<CancelRideSheet> createState() => _CancelRideSheetState();
}

class _CancelRideSheetState extends State<CancelRideSheet> {
  bool _busy = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.driverMatched?.addListener(_onDriverMatched);
    if (widget.driverMatched?.value == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onDriverMatched());
    }
  }

  @override
  void dispose() {
    widget.driverMatched?.removeListener(_onDriverMatched);
    super.dispose();
  }

  void _onDriverMatched() {
    if (widget.driverMatched?.value != true || _busy) return;
    _close(false);
  }

  void _close(bool result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.pop(context, result);
  }

  Future<void> _confirm() async {
    final commit = widget.onConfirm;
    if (commit == null) {
      _close(true);
      return;
    }
    if (_busy || _closed) return;
    setState(() => _busy = true);
    var committed = false;
    try {
      committed = await commit();
    } finally {
      if (mounted) _close(committed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final takingLonger = widget.takingLonger;
    final phase = widget.phase;
    final inset = MediaQuery.paddingOf(context).bottom;
    final matched = phase == CancelPhase.matched;
    final inTrip = phase == CancelPhase.inTrip;
    // UI-01: on board this is the contract's end-early, not a cancel: the
    // trip ends here and the rider pays for the distance driven.
    final body = inTrip
        ? context.l10n.cancelBodyInTrip
        : matched
        ? context.l10n.cancelBodyMatched
        : takingLonger
        ? context.l10n.cancelBodyTakingLonger
        : context.l10n.cancelBodySearching;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 40),
              Expanded(
                child: Text(
                  inTrip ? context.l10n.endTripHereQ : context.l10n.cancelRideQ,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1D252C),
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => _close(false),
                icon: const Icon(Icons.close_rounded),
                tooltip: context.l10n.close,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            inTrip
                ? context.l10n.endBeforeDestinationQ
                : context.l10n.sureToCancelQ,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1D252C),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.poppins(
              fontSize: 14,
              height: 1.4,
              color: const Color(0xFF5C656C),
            ),
          ),
          if (widget.feeNote != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.feeNote!,
              key: const ValueKey('cancel-fee-note'),
              style: GoogleFonts.poppins(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1D252C),
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: TextButton(
              onPressed: _busy ? null : _confirm,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF4F5F6),
                foregroundColor: const Color(0xFFB42318),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFB42318),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          inTrip ? context.l10n.endingTrip : context.l10n.cancelling,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: const Color(0xFFB42318),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      inTrip ? context.l10n.endTripHere : context.l10n.cancelRequest,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: _busy ? null : () => _close(false),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF11181D),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                (matched || inTrip)
                    ? context.l10n.keepRide
                    : takingLonger
                    ? context.l10n.keepSearching
                    : context.l10n.waitForDriver,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
