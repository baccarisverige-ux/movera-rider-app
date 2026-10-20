import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/ride_booking/application/sheet_coordinator.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';

/// Asks why the rider is cancelling.
///
/// With [committed] false (Waiting, reservations) this sheet is the last
/// step before the cancel: Keep ride or dismissing keeps the ride.
///
/// With [committed] true (Finding, cancel-first) the cancel already
/// happened and the reason is optional feedback: there is no Keep ride, and
/// Skip, Send or dismissing all return a cancelled outcome (Send carries the
/// chosen reason).
Future<CancelOutcome> showCancelReasonSheet(
  BuildContext context, {
  required CancelPhase phase,
  bool committed = false,
  bool offerDestinationChange = false,
}) async {
  SheetCoordinator.instance.open(RideSheet.cancelReason);
  final result = await MoveraSheet.show<CancelOutcome>(
    context: context,
    builder: (_) => CancelReasonSheet(
      phase: phase,
      committed: committed,
      offerDestinationChange: offerDestinationChange,
    ),
  );
  SheetCoordinator.instance.close(RideSheet.cancelReason);
  if (committed) return result ?? const CancelOutcome.cancel();
  // Dismissing/backing out never cancels a ride. Cancellation is only
  // committed by an explicit final action inside this sheet.
  return result ?? const CancelOutcome.keep();
}

class CancelReasonSheet extends StatefulWidget {
  const CancelReasonSheet({
    super.key,
    required this.phase,
    this.committed = false,
    this.offerDestinationChange = false,
  });

  final CancelPhase phase;

  /// Q2: picking "Destination needs to be changed" offers the route change
  /// instead (the rider can still cancel). Only where the ride is still
  /// live, so never with [committed].
  final bool offerDestinationChange;

  /// The cancel is already committed; the reason is optional feedback.
  final bool committed;

  @override
  State<CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<CancelReasonSheet> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    final reasons = CancellationReason.forPhase(widget.phase);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, const CancelOutcome.cancel()),
                  child: Text(
                    'Skip',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF5C656C),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.phase == CancelPhase.inTrip
                        ? 'Why are you ending the trip?'
                        : 'Why are you cancelling?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1D252C),
                    ),
                  ),
                ),
                const SizedBox(width: 56),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.committed
                  ? 'Your request is cancelled. Telling us why is optional '
                        'and helps us improve matching.'
                  : widget.phase == CancelPhase.reservation
                  ? 'Optional. This helps us improve scheduled rides.'
                  : widget.phase == CancelPhase.inTrip
                  ? 'Optional. This helps us understand trips that end early.'
                  : 'Optional. This helps us improve matching.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: const Color(0xFF5C656C),
              ),
            ),
            const SizedBox(height: 12),
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: _selected == reason.id
                      ? const Color(0xFFF3F6FB)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: _selected == reason.id
                          ? const Color(0xFF1D252C)
                          : const Color(0xFFE7EBEE),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _selected = reason.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              reason.label,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF1D252C),
                              ),
                            ),
                          ),
                          Icon(
                            _selected == reason.id
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 20,
                            color: _selected == reason.id
                                ? const Color(0xFF1D252C)
                                : const Color(0xFFC5CCD1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.offerDestinationChange &&
                !widget.committed &&
                _selected == CancellationReason.destinationChange.id)
              _DestinationChangeOffer(
                onChange: () => Navigator.pop(
                  context,
                  const CancelOutcome.changeDestination(),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: _selected == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        CancelOutcome.cancel(reasonId: _selected),
                      ),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF4F5F6),
                  foregroundColor: widget.committed
                      ? const Color(0xFF1D252C)
                      : const Color(0xFFB42318),
                  disabledForegroundColor: const Color(0xFFC5CCD1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  widget.committed
                      ? 'Send'
                      : widget.phase == CancelPhase.inTrip
                      ? 'End trip'
                      : 'Cancel ride',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            if (!widget.committed) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, const CancelOutcome.keep()),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF11181D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Keep ride',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Q2: "Change destination instead?" with a button into the route change.
class _DestinationChangeOffer extends StatelessWidget {
  const _DestinationChangeOffer({required this.onChange});

  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('cancel-change-destination-offer'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Change destination instead?',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1D252C),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('cancel-change-destination'),
            onPressed: onChange,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF11181D),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Change destination',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
