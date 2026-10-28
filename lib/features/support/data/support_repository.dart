import 'package:movera_rider/features/support/domain/support.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SupportChatScript {
  SupportChatScript({required this.welcome, String? issueAck, String? followUp})
    : issueAck = issueAck ?? L10n.current.supportIssueAck,
      followUp = followUp ?? L10n.current.supportFollowUp;

  final String welcome;
  final String issueAck;
  final String followUp;
}

/// What the Support message screen says (UI-03, UI-09: no build-state
/// wording). There is no live agent: a message about a ride goes to
/// Movera's review queue.
class SupportRepository {
  /// [ticket]: the rider writes a help ticket without choosing a ride, so
  /// neither the intro nor the reply after sending mentions a ride.
  SupportChatScript chat({SupportRide? ride, bool ticket = false}) {
    if (ride != null) {
      return SupportChatScript(welcome: L10n.current.supportWelcomeRide);
    }
    if (ticket) {
      return SupportChatScript(
        welcome: L10n.current.supportWelcomeTicket,
        issueAck: '',
        followUp: L10n.current.supportFollowUpTicket,
      );
    }
    return SupportChatScript(welcome: L10n.current.supportWelcomeGeneral);
  }
}
