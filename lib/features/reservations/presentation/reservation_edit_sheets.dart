import 'package:flutter/material.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_reason_sheet.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Asks the rider to confirm cancelling [ride], showing what it costs
/// ([terms]) before they confirm.
Future<CancelOutcome> showCancelReservationFlow(
  BuildContext context,
  Reservation ride, {
  required ReservationCancelTerms terms,
}) async {
  final confirmed = await MoveraSheet.show<bool>(
    context: context,
    builder: (sheetContext) {
      final inset = MediaQuery.paddingOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + inset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: kReservationLine,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.resCancelQ,
              style: reservationText(20, weight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.resCancelBody(
                ReservationFormat.weekdayDate(ride.scheduledPickupAt),
                ReservationFormat.time(ride.scheduledPickupAt),
              ),
              style: reservationText(
                14,
                color: kReservationMuted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            ReservationCancelTermsNote(terms: terms),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF4F5F6),
                  foregroundColor: const Color(0xFFB42318),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  context.l10n.cancelReservation,
                  style: reservationText(
                    15,
                    weight: FontWeight.w600,
                    color: const Color(0xFFB42318),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                style: FilledButton.styleFrom(
                  backgroundColor: kReservationCta,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  context.l10n.resKeep,
                  style: reservationText(
                    16,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  if (confirmed != true || !context.mounted) {
    return const CancelOutcome.keep();
  }
  return showCancelReasonSheet(context, phase: CancelPhase.reservation);
}

/// Free-until or fee line shown before the rider confirms a cancel.
class ReservationCancelTermsNote extends StatelessWidget {
  const ReservationCancelTermsNote({super.key, required this.terms});

  final ReservationCancelTerms terms;

  static const _feeTone = Color(0xFFFFF4E5);
  static const _feeInk = Color(0xFF8A4B00);
  static const _freeTone = Color(0xFFEAF2F8);

  @override
  Widget build(BuildContext context) {
    final free = terms.isFree;
    return Container(
      key: Key(free ? 'reservation-cancel-free' : 'reservation-cancel-fee'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: free ? _freeTone : _feeTone,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              free ? Icons.event_available_rounded : Icons.receipt_long_rounded,
              size: 20,
              color: free ? kReservationAccent : _feeInk,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ReservationFormat.cancelTermsTitle(terms),
                  style: reservationText(
                    14.5,
                    weight: FontWeight.w700,
                    color: free ? kReservationInk : _feeInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ReservationFormat.cancelTermsBody(terms),
                  style: reservationText(
                    13,
                    color: kReservationMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
