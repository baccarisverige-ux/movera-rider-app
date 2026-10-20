import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/l10n/l10n.dart';

const Color _terminalInk = Color(0xFF1D252C);
const Color _terminalMuted = Color(0xFF5C656C);
const Color _terminalAction = Color(0xFF2D5878);

/// A backend-owned terminal ride state rendered as an explicit Rider surface.
///
/// This sheet does not create or infer a terminal outcome. It only explains a
/// [RideStatus] that has already arrived from the ride controller/transport.
Future<void> showRideTerminalStateSheet(
  BuildContext context, {
  required RideStatus status,
}) async {
  final spec = RideTerminalStateSpec.fromStatus(status);
  await MoveraSheet.show<void>(
    context: context,
    swipeDismissible: false,
    barrierDismissible: false,
    builder: (sheetContext) => RideTerminalStateSheet(
      status: status,
      spec: spec,
      onAcknowledge: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

/// What the rider chose on the "No driver found" sheet (RIDE-19).
enum NoDriverChoice { tryAgain, changeRoute }

/// "No driver found" after the server ended the search: request the same
/// ride again, or go back to "Where to?" for another route.
Future<NoDriverChoice> showNoDriverFoundSheet(BuildContext context) async {
  final choice = await MoveraSheet.show<NoDriverChoice>(
    context: context,
    swipeDismissible: false,
    barrierDismissible: false,
    builder: (sheetContext) => RideTerminalStateSheet(
      status: RideStatus.noDriverFound,
      spec: RideTerminalStateSpec.noDriverRetry,
      onAcknowledge: () =>
          Navigator.of(sheetContext).pop(NoDriverChoice.tryAgain),
      secondaryLabel: context.l10n.changeRoute,
      onSecondary: () =>
          Navigator.of(sheetContext).pop(NoDriverChoice.changeRoute),
    ),
  );
  return choice ?? NoDriverChoice.changeRoute;
}

class RideTerminalStateSheet extends StatelessWidget {
  const RideTerminalStateSheet({
    super.key,
    required this.status,
    required this.spec,
    required this.onAcknowledge,
    this.secondaryLabel,
    this.onSecondary,
  });

  final RideStatus status;
  final RideTerminalStateSpec spec;
  final VoidCallback onAcknowledge;

  /// Optional second action under the primary button.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottomInset),
        child: Column(
          key: ValueKey<String>('ride-terminal-state-${status.name}'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: spec.iconBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    spec.icon,
                    color: spec.iconColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spec.eyebrow,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _terminalMuted,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          spec.title,
                          style: GoogleFonts.poppins(
                            fontSize: 21,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: _terminalInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              spec.message,
              style: GoogleFonts.poppins(
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w400,
                color: _terminalMuted,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7F8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE6EAEC)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: _terminalMuted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      spec.reassurance,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: _terminalMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey<String>('ride-terminal-acknowledge'),
                onPressed: onAcknowledge,
                style: FilledButton.styleFrom(
                  elevation: 0,
                  backgroundColor: _terminalAction,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  spec.primaryLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const ValueKey<String>('ride-terminal-secondary'),
                  onPressed: onSecondary,
                  style: TextButton.styleFrom(
                    foregroundColor: _terminalAction,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    secondaryLabel!,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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

class RideTerminalStateSpec {
  const RideTerminalStateSpec({
    required this.eyebrow,
    required this.title,
    required this.message,
    required this.reassurance,
    required this.primaryLabel,
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
  });

  final String eyebrow;
  final String title;
  final String message;
  final String reassurance;
  final String primaryLabel;
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;

  /// RIDE-19: "No driver found" when the same request can be sent again.
  static RideTerminalStateSpec get noDriverRetry => RideTerminalStateSpec(
    eyebrow: L10n.current.termRequestEnded,
    title: L10n.current.termNoDriverFound,
    message:
        L10n.current.termNoDriverFoundBody,
    reassurance:
        L10n.current.termNoDriverFoundNote,
    primaryLabel: L10n.current.tryAgain,
    icon: Icons.local_taxi_outlined,
    iconBackground: Color(0xFFEAF1F6),
    iconColor: Color(0xFF2D5878),
  );

  factory RideTerminalStateSpec.fromStatus(RideStatus status) {
    return switch (status) {
      RideStatus.noDriverFound => RideTerminalStateSpec(
          eyebrow: L10n.current.termRequestEnded,
          title: L10n.current.termNoDriverAvailable,
          message:
              L10n.current.termNoDriverAvailableBody,
          reassurance:
              L10n.current.termNoDriverAvailableNote,
          primaryLabel: L10n.current.backToHome,
          icon: Icons.local_taxi_outlined,
          iconBackground: Color(0xFFEAF1F6),
          iconColor: Color(0xFF2D5878),
        ),
      RideStatus.bookingExpired => RideTerminalStateSpec(
          eyebrow: L10n.current.termRequestExpired,
          title: L10n.current.termBookingExpired,
          message:
              L10n.current.termBookingExpiredBody,
          reassurance:
              L10n.current.termBookingExpiredNote,
          primaryLabel: L10n.current.backToHome,
          icon: Icons.schedule_rounded,
          iconBackground: Color(0xFFFFF3DE),
          iconColor: Color(0xFF9A6414),
        ),
      RideStatus.paymentFailed => RideTerminalStateSpec(
          eyebrow: L10n.current.termPaymentEyebrow,
          title: L10n.current.termPaymentTitle,
          message:
              L10n.current.termPaymentBody,
          reassurance:
              L10n.current.termPaymentNote,
          primaryLabel: L10n.current.backToHome,
          icon: Icons.credit_card_off_outlined,
          iconBackground: Color(0xFFF8E8E6),
          iconColor: Color(0xFF9B3B34),
        ),
      RideStatus.cancelledBySystem => RideTerminalStateSpec(
          eyebrow: L10n.current.termRideEnded,
          title: L10n.current.termSystemTitle,
          message:
              L10n.current.termSystemBody,
          reassurance:
              L10n.current.termSystemNote,
          primaryLabel: L10n.current.backToHome,
          icon: Icons.info_outline_rounded,
          iconBackground: Color(0xFFEAF1F6),
          iconColor: Color(0xFF2D5878),
        ),
      RideStatus.cancelledByDriver => RideTerminalStateSpec(
          eyebrow: L10n.current.termDriverUpdate,
          title: L10n.current.driverCancelled,
          message:
              L10n.current.termDriverCancelledBody,
          reassurance:
              L10n.current.termDriverCancelledNote,
          primaryLabel: L10n.current.continueLabel,
          icon: Icons.person_off_outlined,
          iconBackground: Color(0xFFF8E8E6),
          iconColor: Color(0xFF9B3B34),
        ),
      // Contract v0.3.0: each terminal cause has its own copy.
      RideStatus.cancelledByAdmin => RideTerminalStateSpec(
          eyebrow: L10n.current.termRideCancelled,
          title: L10n.current.cancelledByMovera,
          message:
              L10n.current.termAdminBody,
          reassurance:
              L10n.current.termAdminNote,
          primaryLabel: L10n.current.backToHome,
          icon: Icons.support_agent_rounded,
          iconBackground: Color(0xFFEAF1F6),
          iconColor: Color(0xFF2D5878),
        ),
      RideStatus.noShow => RideTerminalStateSpec(
          eyebrow: L10n.current.termRideEnded,
          title: L10n.current.termNoShowTitle,
          message:
              L10n.current.termNoShowBody,
          reassurance:
              L10n.current.termNoShowNote,
          primaryLabel: L10n.current.backToHome,
          icon: Icons.person_search_rounded,
          iconBackground: Color(0xFFFFF3DE),
          iconColor: Color(0xFF9A6414),
        ),
      RideStatus.tripFailed => RideTerminalStateSpec(
          eyebrow: L10n.current.termFailedEyebrow,
          title: L10n.current.termFailedTitle,
          message:
              L10n.current.termFailedBody,
          reassurance:
              L10n.current.termFailedNote,
          primaryLabel: L10n.current.backToHome,
          icon: Icons.error_outline_rounded,
          iconBackground: Color(0xFFF8E8E6),
          iconColor: Color(0xFF9B3B34),
        ),
      RideStatus.endedByDriver => RideTerminalStateSpec(
          eyebrow: L10n.current.termRideEnded,
          title: L10n.current.termEndedByDriverTitle,
          message:
              L10n.current.termEndedByDriverBody,
          reassurance:
              L10n.current.termEndedByDriverNote,
          primaryLabel: L10n.current.backToHome,
          icon: Icons.person_off_outlined,
          iconBackground: Color(0xFFF8E8E6),
          iconColor: Color(0xFF9B3B34),
        ),
      _ => RideTerminalStateSpec(
          eyebrow: L10n.current.termRideEnded,
          title: L10n.current.termGenericTitle,
          message:
              L10n.current.termGenericBody,
          reassurance:
              L10n.current.termGenericNote,
          primaryLabel: L10n.current.backToHome,
          icon: Icons.info_outline_rounded,
          iconBackground: Color(0xFFEAF1F6),
          iconColor: Color(0xFF2D5878),
        ),
    };
  }
}
