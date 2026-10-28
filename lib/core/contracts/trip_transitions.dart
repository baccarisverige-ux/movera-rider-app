import 'package:movera_rider/core/contracts/trip_status.dart';

/// Who issues a trip command (`contract.json#actors`). The server derives
/// it from the token; it is never read from a request body.
enum TripActor { rider, driver, admin, system }

/// `kind` of a trip: some commands lead elsewhere for a reservation.
enum TripKind { live, scheduled }

extension TripActorWire on TripActor {
  String get wireName => name;

  static TripActor? parse(Object? raw) {
    if (raw is! String) return null;
    for (final actor in TripActor.values) {
      if (actor.name == raw.trim()) return actor;
    }
    return null;
  }
}

extension TripKindWire on TripKind {
  String get wireName => name;

  static TripKind? parse(Object? raw) {
    if (raw is! String) return null;
    for (final kind in TripKind.values) {
      if (kind.name == raw.trim()) return kind;
    }
    return null;
  }
}

/// One row of `contract.json#transitions`: [command] by [actor] from any of
/// [from] leads to [to]; [when] restricts the row to one trip kind.
class TripTransition {
  const TripTransition(
    this.command,
    this.actor,
    this.from,
    this.to, {
    this.when,
  });

  final String command;
  final TripActor actor;
  final Set<TripStatus> from;
  final TripStatus to;
  final TripKind? when;

  bool matches(
    TripStatus status,
    String command,
    TripActor actor,
    TripKind kind,
  ) =>
      this.command == command &&
      this.actor == actor &&
      from.contains(status) &&
      (when == null || when == kind);
}

/// The single trip state machine, a pure mirror of
/// `contract.json#transitions` (v0.5.5). A contract test checks this table
/// row by row against the shipped `contracts/contract.json` and replays
/// `fixtures/scenarios.json` through [TripStateMachine.apply].
///
/// Anything not in the table is `409 invalid_transition` and the status does
/// not change.
abstract final class TripStateMachine {
  static const contractVersion = '0.9.0';

  static const _s = TripStatus.searching;
  static const _o = TripStatus.offered;
  static const _rq = TripStatus.requested;
  static const _a = TripStatus.accepted;
  static const _dp = TripStatus.driverToPickup;
  static const _ar = TripStatus.arrived;
  static const _ob = TripStatus.riderOnboard;
  static const _it = TripStatus.inTrip;
  static const _ad = TripStatus.approachingDropoff;

  static const List<TripTransition> transitions = [
    TripTransition('quote', TripActor.system, {
      TripStatus.draft,
    }, TripStatus.quoted),
    TripTransition('request', TripActor.rider, {TripStatus.quoted}, _rq),
    TripTransition('start_search', TripActor.system, {_rq}, _s),
    // v0.5.5 (§3.6): the rider raises their offer while searching.
    TripTransition('raise_price', TripActor.rider, {_o, _s}, _s),
    TripTransition('send_offer', TripActor.system, {_s}, _o),
    TripTransition('offer_lapsed', TripActor.system, {_o}, _s),
    // v0.5.1: a live trip is accepted only from offered; from requested
    // only a scheduled trip the driver claims early.
    TripTransition('accept', TripActor.driver, {_o}, _a),
    TripTransition(
      'accept',
      TripActor.driver,
      {_rq},
      _a,
      when: TripKind.scheduled,
    ),
    TripTransition('assign', TripActor.admin, {_rq, _s, _o}, _o),
    TripTransition('head_to_pickup', TripActor.driver, {_a}, _dp),
    TripTransition('arrive', TripActor.driver, {_dp}, _ar),
    TripTransition('board', TripActor.driver, {_ar}, _ob),
    TripTransition('start_trip', TripActor.driver, {_ob}, _it),
    TripTransition('near_dropoff', TripActor.system, {_it}, _ad),
    TripTransition('complete', TripActor.driver, {
      _it,
      _ad,
    }, TripStatus.completed),
    TripTransition('complete', TripActor.admin, {
      _ob,
      _it,
      _ad,
    }, TripStatus.completed),
    TripTransition('cancel', TripActor.rider, {
      _rq,
      _s,
      _o,
      _a,
      _dp,
      _ar,
    }, TripStatus.cancelledByRider),
    TripTransition('end_early', TripActor.rider, {
      _ob,
      _it,
      _ad,
    }, TripStatus.cancelledByRider),
    TripTransition(
      'cancel',
      TripActor.driver,
      {_a, _dp, _ar},
      _s,
      when: TripKind.live,
    ),
    TripTransition(
      'cancel',
      TripActor.driver,
      {_a},
      _rq,
      when: TripKind.scheduled,
    ),
    TripTransition(
      'cancel',
      TripActor.driver,
      {_dp, _ar},
      _s,
      when: TripKind.scheduled,
    ),
    TripTransition('cancel', TripActor.driver, {
      _ob,
      _it,
      _ad,
    }, TripStatus.cancelledByDriver),
    TripTransition('no_show', TripActor.driver, {_ar}, TripStatus.noShow),
    TripTransition('no_show', TripActor.admin, {
      _ar,
      _a,
      _dp,
    }, TripStatus.noShow),
    TripTransition('reassign', TripActor.admin, {_o, _a, _dp, _ar}, _s),
    TripTransition('cancel', TripActor.admin, {
      TripStatus.draft,
      TripStatus.quoted,
      _rq,
      _s,
      _o,
      _a,
      _dp,
      _ar,
      _ob,
      _it,
      _ad,
    }, TripStatus.cancelledByAdmin),
    TripTransition('expire', TripActor.system, {
      TripStatus.quoted,
      _rq,
      _s,
      _o,
    }, TripStatus.expired),
    TripTransition('system_cancel', TripActor.system, {
      _rq,
      _s,
      _o,
      _a,
    }, TripStatus.cancelledBySystem),
    TripTransition('fail', TripActor.system, {
      _rq,
      _s,
      _o,
      _a,
      _dp,
      _ar,
      _ob,
      _it,
      _ad,
    }, TripStatus.failed),
  ];

  /// Every command name the table knows.
  static Set<String> get commands => {for (final t in transitions) t.command};

  /// The status after [command] by [actor] from [status], or null when the
  /// contract does not allow it (`invalid_transition`). Terminal statuses
  /// have no outgoing rows, so they never change.
  static TripStatus? apply(
    TripStatus status,
    String command,
    TripActor actor, {
    TripKind kind = TripKind.live,
  }) {
    for (final transition in transitions) {
      if (transition.matches(status, command, actor, kind)) {
        return transition.to;
      }
    }
    return null;
  }

  static bool allows(
    TripStatus status,
    String command,
    TripActor actor, {
    TripKind kind = TripKind.live,
  }) => apply(status, command, actor, kind: kind) != null;

  /// The shortest legal command path from [from] to [to], trying commands
  /// by [actors] in table order, or null when there is none. The stand-in
  /// server's simulator uses it to walk a trip forward (driver and system
  /// steps) one legal transition at a time.
  static List<(String, TripActor)>? pathTo(
    TripStatus from,
    TripStatus to, {
    TripKind kind = TripKind.live,
    Set<TripActor> actors = const {TripActor.driver, TripActor.system},
  }) {
    if (from == to) return const [];
    final previous = <TripStatus, (TripStatus, String, TripActor)>{};
    final queue = <TripStatus>[from];
    final seen = <TripStatus>{from};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final t in transitions) {
        if (!actors.contains(t.actor) || !t.from.contains(current)) continue;
        if (t.when != null && t.when != kind) continue;
        if (!seen.add(t.to)) continue;
        previous[t.to] = (current, t.command, t.actor);
        if (t.to == to) {
          final path = <(String, TripActor)>[];
          var at = to;
          while (at != from) {
            final (before, command, actor) = previous[at]!;
            path.insert(0, (command, actor));
            at = before;
          }
          return path;
        }
        queue.add(t.to);
      }
    }
    return null;
  }
}

/// One row of `contract.json#ratingAllowed.rules`: [rater] may rate a trip
/// that ended in [status], through [command] when it is set.
class TripRatingRule {
  const TripRatingRule(this.rater, this.status, {this.command});

  final TripActor rater;
  final TripStatus status;
  final String? command;
}

/// Who may rate a finished trip, a pure mirror of
/// `contract.json#ratingAllowed` (v0.3.1). The rider rates a completed trip
/// and one they ended early (`end_early` → `cancelled_by_rider`); a plain
/// rider `cancel` is never rated. Anything else is `409 invalid_transition`.
/// A contract test checks the rows and replays the `rating` cases of
/// `fixtures/scenarios.json`.
abstract final class TripRatingRules {
  static const List<TripRatingRule> rules = [
    TripRatingRule(TripActor.rider, TripStatus.completed),
    TripRatingRule(TripActor.driver, TripStatus.completed),
    TripRatingRule(
      TripActor.rider,
      TripStatus.cancelledByRider,
      command: 'end_early',
    ),
  ];

  /// Whether [rater] may rate a trip in [status] that [endedBy] (the
  /// command that ended it, when known) brought there.
  static bool allows(TripActor rater, TripStatus status, {String? endedBy}) =>
      rules.any(
        (rule) =>
            rule.rater == rater &&
            rule.status == status &&
            (rule.command == null || rule.command == endedBy),
      );
}
