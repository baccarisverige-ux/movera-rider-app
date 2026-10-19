import 'package:movera_rider/features/support/domain/support.dart';

class SupportChatScript {
  const SupportChatScript({
    required this.welcome,
    this.issueAck =
        'Add any details below, then send it to Movera. The ride details are included.',
    this.followUp =
        'Sent to Movera. The team reviews it together with this ride’s details.',
  });

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
      return const SupportChatScript(
        welcome: 'Tell us what happened on this ride.',
      );
    }
    return const SupportChatScript(
      welcome:
          'To send Movera a message from the app, choose the ride it’s about. '
          'Help articles and the Safety tools are always available.',
    );
  }
}
