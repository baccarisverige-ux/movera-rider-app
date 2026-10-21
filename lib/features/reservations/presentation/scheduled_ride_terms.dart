import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation_policy.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/l10n/l10n.dart';

class ScheduledRideTermsPage extends StatelessWidget {
  const ScheduledRideTermsPage({
    super.key,
    this.controller,
    this.policy,
    this.reservationId,
  });

  final ReservationController? controller;
  final ReservationPolicy? policy;

  /// rider-u169: the reservation the page was opened from. Its own cancel
  /// rule (the zone's rule for its ride type) is the one stated.
  final String? reservationId;

  static Future<void> open(
    BuildContext context, {
    ReservationController? controller,
    String? reservationId,
  }) {
    return Navigator.push(
      context,
      RightToLeftTransition(
        ScheduledRideTermsPage(
          controller: controller,
          reservationId: reservationId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final terms =
        policy ?? controller?.policy ?? AppScope.instance.reservations.policy;
    final reservations = controller ?? AppScope.instance.reservations;
    final id = reservationId;
    final ride = id == null ? null : reservations.byId(id);
    final cancelRule = ride == null
        ? ReservationFormat.cancelRule(reservations.rules)
        : ReservationFormat.cancelRuleOf(reservations.cancelTermsFor(ride));
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: top + 4),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: kReservationInk),
            tooltip: context.l10n.close,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
              children: [
                Text(
                  context.l10n.resTermsTitle,
                  style: reservationText(
                    30,
                    weight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.resTermsOtherFees(cancelRule),
                  key: const Key('scheduled-terms-cancel-rule'),
                  style: reservationText(
                    14,
                    color: kReservationMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  terms.pricingDisclaimer,
                  style: reservationText(14.5, height: 1.45),
                ),
                const SizedBox(height: 12),
                Text(
                  terms.assignmentDisclaimer,
                  style: reservationText(14.5, height: 1.45),
                ),
                const SizedBox(height: 28),
                for (final section in terms.sections) ...[
                  Text(
                    section.title,
                    style: reservationText(16, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    section.body,
                    style: reservationText(
                      14,
                      color: kReservationMuted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
