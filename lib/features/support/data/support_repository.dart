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
  SupportChatScript chat({SupportRide? ride}) {
    if (ride != null) {
      return SupportChatScript(welcome: L10n.current.supportWelcomeRide);
    }
    return SupportChatScript(welcome: L10n.current.supportWelcomeGeneral);
  }
}
