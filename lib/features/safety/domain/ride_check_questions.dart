import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/l10n/l10n.dart';

// The English labels below are saved with the rider's answers (the safety
// team reads them); the card shows the `display…` text in the app language.

/// The rider's "Or tell us what happened" rows.
enum RideCheckRowId {
  accident,
  hurt,
  unsafe,
  wrongPlace,
  askedToLeave,
  carBrokeDown,
  askedStop,
  askedRoute,
  somethingElse,
}

/// The answers a follow-up question offers.
enum RideCheckOptionId { yes, no, notSure, me, driver, someoneElse }

class RideCheckOption {
  const RideCheckOption(this.id, this.label);

  final RideCheckOptionId id;
  final String label;

  /// [label] in the app language.
  String get displayLabel => switch (id) {
    RideCheckOptionId.yes => L10n.current.rcYes,
    RideCheckOptionId.no => L10n.current.rcNo,
    RideCheckOptionId.notSure => L10n.current.rcNotSure,
    RideCheckOptionId.me => L10n.current.rcMe,
    RideCheckOptionId.driver => L10n.current.rcTheDriver,
    RideCheckOptionId.someoneElse => L10n.current.rcSomeoneElse,
  };

  /// RC4: a "Yes" or "Not sure" updates the alert. Naming who needs help
  /// says the same thing, so it does too.
  bool get updatesAlert => switch (id) {
    RideCheckOptionId.yes ||
    RideCheckOptionId.notSure ||
    RideCheckOptionId.me ||
    RideCheckOptionId.driver ||
    RideCheckOptionId.someoneElse => true,
    RideCheckOptionId.no => false,
  };
}

const _yes = RideCheckOption(RideCheckOptionId.yes, 'Yes');
const _no = RideCheckOption(RideCheckOptionId.no, 'No');
const _notSure = RideCheckOption(RideCheckOptionId.notSure, 'Not sure');

class RideCheckQuestion {
  const RideCheckQuestion({
    required this.id,
    required this.text,
    required this.options,
    this.callWhen = const {},
  });

  /// Stable id saved with the answer, e.g. `anyone_hurt`.
  final String id;
  final String text;
  final List<RideCheckOption> options;

  /// [text] in the app language.
  String get displayText => rideCheckQuestionText(id) ?? text;

  /// Answers that bring up the big "Call 112 now".
  final Set<RideCheckOptionId> callWhen;

  RideCheckOption? option(RideCheckOptionId id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }
}

/// What the card asks after a row is tapped.
class RideCheckFollowUp {
  const RideCheckFollowUp({
    required this.heading,
    this.questions = const [],
    this.asksForNote = false,
  });

  /// The caps after "RIDE CHECK ·", e.g. "Accident".
  final String heading;
  final List<RideCheckQuestion> questions;

  /// [heading] in the app language.
  String get displayHeading => switch (heading) {
    'Accident' => L10n.current.rcHeadAccident,
    'Someone hurt' => L10n.current.rcHeadSomeoneHurt,
    'Unsafe' => L10n.current.rcHeadUnsafe,
    'Car problem' => L10n.current.rcHeadCarProblem,
    'Something else' => L10n.current.rcHeadSomethingElse,
    'Wrong place' => L10n.current.rcHeadWrongPlace,
    'Asked to leave' => L10n.current.rcHeadAskedToLeave,
    'Stop' => L10n.current.rcHeadStop,
    'Route' => L10n.current.rcHeadRoute,
    _ => heading,
  };

  /// "Something else": a short text field.
  final bool asksForNote;

  /// Rows with nothing to ask just say the answer is saved.
  bool get thanksOnly => questions.isEmpty && !asksForNote;

  RideCheckQuestion? question(String id) {
    for (final question in questions) {
      if (question.id == id) return question;
    }
    return null;
  }
}

class RideCheckRow {
  const RideCheckRow({
    required this.id,
    required this.label,
    required this.followUp,
    this.red = false,
  });

  final RideCheckRowId id;
  final String label;
  final RideCheckFollowUp followUp;

  /// [label] in the app language.
  String get displayLabel => switch (id) {
    RideCheckRowId.accident => L10n.current.rcRowAccident,
    RideCheckRowId.hurt => L10n.current.rcRowHurt,
    RideCheckRowId.unsafe => L10n.current.rcRowUnsafe,
    RideCheckRowId.wrongPlace => L10n.current.rcRowWrongPlace,
    RideCheckRowId.askedToLeave => L10n.current.rcRowAskedToLeave,
    RideCheckRowId.carBrokeDown => L10n.current.rcRowCarBrokeDown,
    RideCheckRowId.askedStop => L10n.current.rcRowAskedStop,
    RideCheckRowId.askedRoute => L10n.current.rcRowAskedRoute,
    RideCheckRowId.somethingElse => L10n.current.rcRowSomethingElse,
  };

  /// Red rows alert the Movera safety team the moment they are tapped (RC4).
  final bool red;

  String get wire => switch (id) {
    RideCheckRowId.accident => 'accident',
    RideCheckRowId.hurt => 'someone_hurt',
    RideCheckRowId.unsafe => 'feel_unsafe',
    RideCheckRowId.wrongPlace => 'wrong_place',
    RideCheckRowId.askedToLeave => 'asked_to_leave',
    RideCheckRowId.carBrokeDown => 'car_broke_down',
    RideCheckRowId.askedStop => 'asked_to_stop',
    RideCheckRowId.askedRoute => 'asked_for_route',
    RideCheckRowId.somethingElse => 'something_else',
  };
}

/// The one line a thanks-only row shows.
String get rideCheckThanksLine => L10n.current.rcThanksSaved;

/// A follow-up question's text in the app language, by its saved id.
String? rideCheckQuestionText(String id) => switch (id) {
  'anyone_hurt' => L10n.current.rcQAnyoneHurt,
  'car_safe_place' => L10n.current.rcQCarSafePlace,
  'other_person_ok' => L10n.current.rcQOtherPersonOk,
  'who_needs_help' => L10n.current.rcQWhoNeedsHelp,
  'in_danger' => L10n.current.rcQInDanger,
  'can_continue' => L10n.current.rcQCanContinue,
  _ => null,
};

/// A saved option (`yes`, `not_sure`, ...) in the app language.
String? rideCheckOptionText(String wire) => switch (wire) {
  'yes' => L10n.current.rcYes,
  'no' => L10n.current.rcNo,
  'not_sure' => L10n.current.rcNotSure,
  'me' => L10n.current.rcMe,
  'the_driver' => L10n.current.rcTheDriver,
  'someone_else' => L10n.current.rcSomeoneElse,
  _ => null,
};

const _accident = RideCheckRow(
  id: RideCheckRowId.accident,
  label: 'There was an accident',
  red: true,
  followUp: RideCheckFollowUp(
    heading: 'Accident',
    questions: [
      RideCheckQuestion(
        id: 'anyone_hurt',
        text: 'Is anyone hurt?',
        options: [_yes, _no, _notSure],
        callWhen: {RideCheckOptionId.yes, RideCheckOptionId.notSure},
      ),
      RideCheckQuestion(
        id: 'car_safe_place',
        text: 'Is the car in a safe place?',
        options: [_yes, _no],
      ),
      RideCheckQuestion(
        id: 'other_person_ok',
        text: 'Is the other person OK?',
        options: [_yes, _no, _notSure],
      ),
    ],
  ),
);

const _hurt = RideCheckRow(
  id: RideCheckRowId.hurt,
  label: 'Someone is hurt or feels ill',
  red: true,
  followUp: RideCheckFollowUp(
    heading: 'Someone hurt',
    questions: [
      RideCheckQuestion(
        id: 'who_needs_help',
        text: 'Who needs help?',
        options: [
          RideCheckOption(RideCheckOptionId.me, 'Me'),
          RideCheckOption(RideCheckOptionId.driver, 'The driver'),
          RideCheckOption(RideCheckOptionId.someoneElse, 'Someone else'),
        ],
        callWhen: {
          RideCheckOptionId.me,
          RideCheckOptionId.driver,
          RideCheckOptionId.someoneElse,
        },
      ),
    ],
  ),
);

const _unsafe = RideCheckRow(
  id: RideCheckRowId.unsafe,
  label: 'I feel unsafe',
  red: true,
  followUp: RideCheckFollowUp(
    heading: 'Unsafe',
    questions: [
      RideCheckQuestion(
        id: 'in_danger',
        text: 'Are you in danger right now?',
        options: [_yes, _no],
        callWhen: {RideCheckOptionId.yes},
      ),
    ],
  ),
);

const _carBrokeDown = RideCheckRow(
  id: RideCheckRowId.carBrokeDown,
  label: 'The car broke down',
  followUp: RideCheckFollowUp(
    heading: 'Car problem',
    questions: [
      RideCheckQuestion(
        id: 'can_continue',
        text: 'Can you continue the trip?',
        options: [_yes, _no],
      ),
    ],
  ),
);

const _somethingElse = RideCheckRow(
  id: RideCheckRowId.somethingElse,
  label: 'Something else',
  followUp: RideCheckFollowUp(heading: 'Something else', asksForNote: true),
);

const _wrongPlace = RideCheckRow(
  id: RideCheckRowId.wrongPlace,
  label: 'I was left at the wrong place',
  followUp: RideCheckFollowUp(heading: 'Wrong place'),
);

const _askedToLeave = RideCheckRow(
  id: RideCheckRowId.askedToLeave,
  label: 'The driver asked me to leave the car',
  followUp: RideCheckFollowUp(heading: 'Asked to leave'),
);

const _askedStop = RideCheckRow(
  id: RideCheckRowId.askedStop,
  label: 'I asked the driver to stop',
  followUp: RideCheckFollowUp(heading: 'Stop'),
);

const _askedRoute = RideCheckRow(
  id: RideCheckRowId.askedRoute,
  label: 'I asked for this route',
  followUp: RideCheckFollowUp(heading: 'Route'),
);

/// Every rider row, for reading saved answers back.
const List<RideCheckRow> rideCheckAllRows = [
  _accident,
  _hurt,
  _unsafe,
  _wrongPlace,
  _askedToLeave,
  _carBrokeDown,
  _askedStop,
  _askedRoute,
  _somethingElse,
];

RideCheckRow rideCheckRow(RideCheckRowId id) => switch (id) {
  RideCheckRowId.accident => _accident,
  RideCheckRowId.hurt => _hurt,
  RideCheckRowId.unsafe => _unsafe,
  RideCheckRowId.wrongPlace => _wrongPlace,
  RideCheckRowId.askedToLeave => _askedToLeave,
  RideCheckRowId.carBrokeDown => _carBrokeDown,
  RideCheckRowId.askedStop => _askedStop,
  RideCheckRowId.askedRoute => _askedRoute,
  RideCheckRowId.somethingElse => _somethingElse,
};

/// The rider's rows for [trigger]: the three red ones always first, then the
/// trigger's own. A possible crash asks what a long stop asks.
List<RideCheckRow> rideCheckRowsFor(RideCheckTrigger trigger) {
  const red = [_accident, _hurt, _unsafe];
  return switch (trigger) {
    RideCheckTrigger.droppedFar => const [
      ...red,
      _wrongPlace,
      _askedToLeave,
      _carBrokeDown,
      _somethingElse,
    ],
    RideCheckTrigger.offRoute => const [
      ...red,
      _askedRoute,
      _carBrokeDown,
      _somethingElse,
    ],
    RideCheckTrigger.longStop || RideCheckTrigger.possibleCrash => const [
      ...red,
      _askedStop,
      _carBrokeDown,
      _somethingElse,
    ],
  };
}
