import 'package:movera_rider/features/reservations/domain/reservation_policy.dart';
import 'package:movera_rider/l10n/l10n.dart';

class ReservationPolicyCatalog {
  /// The terms in the app language (read each time, so a language change
  /// shows at once).
  static ReservationPolicy get current {
    final l = L10n.current;
    return ReservationPolicy(
      version: 'unpublished.v1',
      pricingDisclaimer: l.polPricingDisclaimer,
      assignmentDisclaimer: l.polAssignmentDisclaimer,
      waitingSummary: l.polWaitingSummary,
      cancellationSummary: l.polCancellationSummary,
      pricingSummary: l.polPricingSummary,
      sections: [
        ReservationPolicySection(
          title: l.polPricingTitle,
          body: l.polPricingBody,
        ),
        ReservationPolicySection(
          title: l.polAssignTitle,
          body: l.polAssignBody,
        ),
        ReservationPolicySection(title: l.polWaitTitle, body: l.polWaitBody),
        ReservationPolicySection(
          title: l.polCancelTermsTitle,
          body: l.polCancelTermsBody,
        ),
        ReservationPolicySection(
          title: l.polCancelFeesTitle,
          body: l.polCancelFeesBody,
        ),
        ReservationPolicySection(
          title: l.polChangesTitle,
          body: l.polChangesBody,
        ),
        ReservationPolicySection(
          title: l.polNoDriverTitle,
          body: l.polNoDriverBody,
        ),
        ReservationPolicySection(
          title: l.polPromotionsTitle,
          body: l.polPromotionsBody,
        ),
        ReservationPolicySection(
          title: l.polResponsibilitiesTitle,
          body: l.polResponsibilitiesBody,
        ),
      ],
    );
  }
}
