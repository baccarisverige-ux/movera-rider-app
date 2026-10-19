import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';

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
      secondaryLabel: 'Change route',
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
  static const noDriverRetry = RideTerminalStateSpec(
    eyebrow: 'REQUEST ENDED',
    title: 'No driver found',
    message:
        'No driver accepted this request, so the ride did not start. You can request the same ride again or choose a different route.',
    reassurance:
        'Try again keeps your pickup, destination, ride type and payment.',
    primaryLabel: 'Try again',
    icon: Icons.local_taxi_outlined,
    iconBackground: Color(0xFFEAF1F6),
    iconColor: Color(0xFF2D5878),
  );

  factory RideTerminalStateSpec.fromStatus(RideStatus status) {
    return switch (status) {
      RideStatus.noDriverFound => const RideTerminalStateSpec(
          eyebrow: 'REQUEST ENDED',
          title: 'No driver was available',
          message:
              'We could not confirm a driver for this request. The ride did not start, so you can return home and request again when you are ready.',
          reassurance:
              'Your pickup and destination can be selected again from Home.',
          primaryLabel: 'Back to home',
          icon: Icons.local_taxi_outlined,
          iconBackground: Color(0xFFEAF1F6),
          iconColor: Color(0xFF2D5878),
        ),
      RideStatus.bookingExpired => const RideTerminalStateSpec(
          eyebrow: 'REQUEST EXPIRED',
          title: 'This booking expired',
          message:
              'The request was not confirmed in time and is no longer active. No driver is assigned to this booking.',
          reassurance:
              'Return home to create a fresh request with current availability.',
          primaryLabel: 'Back to home',
          icon: Icons.schedule_rounded,
          iconBackground: Color(0xFFFFF3DE),
          iconColor: Color(0xFF9A6414),
        ),
      RideStatus.paymentFailed => const RideTerminalStateSpec(
          eyebrow: 'PAYMENT NOT COMPLETED',
          title: 'Payment could not be completed',
          message:
              'Movera could not finalize the payment step for this ride. The trip is not active.',
          reassurance:
              'You can review your payment method before requesting another ride.',
          primaryLabel: 'Back to home',
          icon: Icons.credit_card_off_outlined,
          iconBackground: Color(0xFFF8E8E6),
          iconColor: Color(0xFF9B3B34),
        ),
      RideStatus.cancelledBySystem => const RideTerminalStateSpec(
          eyebrow: 'RIDE ENDED',
          title: 'Movera ended this ride',
          message:
              'The ride was closed by the platform and is no longer active. Return home before starting another request.',
          reassurance:
              'Your next request will start as a new trip and will not reuse this ride state.',
          primaryLabel: 'Back to home',
          icon: Icons.info_outline_rounded,
          iconBackground: Color(0xFFEAF1F6),
          iconColor: Color(0xFF2D5878),
        ),
      RideStatus.cancelledByDriver => const RideTerminalStateSpec(
          eyebrow: 'DRIVER UPDATE',
          title: 'Your driver cancelled',
          message:
              'This assigned driver is no longer on the ride. Movera will only continue matching when the ride flow explicitly requests a new driver.',
          reassurance:
              'Your ride details are kept separate from the cancelled driver assignment.',
          primaryLabel: 'Continue',
          icon: Icons.person_off_outlined,
          iconBackground: Color(0xFFF8E8E6),
          iconColor: Color(0xFF9B3B34),
        ),
      // Contract v0.3.0: each terminal cause has its own copy.
      RideStatus.cancelledByAdmin => const RideTerminalStateSpec(
          eyebrow: 'RIDE CANCELLED',
          title: 'Cancelled by Movera',
          message:
              'Movera support cancelled this ride. It is no longer active and no driver is on the way.',
          reassurance:
              'Contact support from Help if you did not expect this.',
          primaryLabel: 'Back to home',
          icon: Icons.support_agent_rounded,
          iconBackground: Color(0xFFEAF1F6),
          iconColor: Color(0xFF2D5878),
        ),
      RideStatus.noShow => const RideTerminalStateSpec(
          eyebrow: 'RIDE ENDED',
          title: 'Your driver could not find you',
          message:
              'The driver waited at the pickup point and the ride was closed as a no-show. A no-show fee may apply.',
          reassurance:
              'You can see any fee on your receipt in History, or contact support from Help.',
          primaryLabel: 'Back to home',
          icon: Icons.person_search_rounded,
          iconBackground: Color(0xFFFFF3DE),
          iconColor: Color(0xFF9A6414),
        ),
      RideStatus.tripFailed => const RideTerminalStateSpec(
          eyebrow: 'SOMETHING WENT WRONG',
          title: 'This ride could not continue',
          message:
              'A problem on our side stopped this ride. It is no longer active.',
          reassurance:
              'Contact support from Help and we will sort out anything you were charged.',
          primaryLabel: 'Back to home',
          icon: Icons.error_outline_rounded,
          iconBackground: Color(0xFFF8E8E6),
          iconColor: Color(0xFF9B3B34),
        ),
      RideStatus.endedByDriver => const RideTerminalStateSpec(
          eyebrow: 'RIDE ENDED',
          title: 'Your driver ended the ride',
          message:
              'The driver ended this ride before the destination. It is no longer active.',
          reassurance:
              'You pay only for the distance driven. Contact support from Help if something happened.',
          primaryLabel: 'Back to home',
          icon: Icons.person_off_outlined,
          iconBackground: Color(0xFFF8E8E6),
          iconColor: Color(0xFF9B3B34),
        ),
      _ => const RideTerminalStateSpec(
          eyebrow: 'RIDE ENDED',
          title: 'This ride is no longer active',
          message:
              'The current ride has reached a terminal state and cannot continue from this screen.',
          reassurance:
              'Return home before starting a new ride request.',
          primaryLabel: 'Back to home',
          icon: Icons.info_outline_rounded,
          iconBackground: Color(0xFFEAF1F6),
          iconColor: Color(0xFF2D5878),
        ),
    };
  }
}
