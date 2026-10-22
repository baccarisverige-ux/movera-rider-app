import 'package:movera_rider/l10n/l10n.dart';

enum CancelPhase { searching, matched, inTrip, reservation }

class CancellationReason {
  const CancellationReason({required this.id, required String label})
    : _label = label;

  final String id;

  /// English, for an id the app has no translation for.
  final String _label;

  /// What the rider reads, in the app language.
  String get label => switch (id) {
    'pickup_incorrect' => L10n.current.cancelReasonPickupIncorrect,
    'wrong_ride_option' => L10n.current.cancelReasonWrongRideOption,
    'requested_by_mistake' => L10n.current.cancelReasonByMistake,
    'wait_too_long' => L10n.current.cancelReasonWaitTooLong,
    'destination_change' => L10n.current.cancelReasonDestinationChange,
    'driver_not_suitable' => L10n.current.cancelReasonDriverNotSuitable,
    'plans_changed' => L10n.current.cancelReasonPlansChanged,
    'something_else' => L10n.current.cancelReasonSomethingElse,
    _ => _label,
  };

  static const pickupIncorrect = CancellationReason(
    id: 'pickup_incorrect',
    label: 'Pickup point is incorrect',
  );
  static const wrongRideOption = CancellationReason(
    id: 'wrong_ride_option',
    label: 'I chose the wrong ride option',
  );
  static const requestedByMistake = CancellationReason(
    id: 'requested_by_mistake',
    label: 'I requested the ride by mistake',
  );
  static const waitTooLong = CancellationReason(
    id: 'wait_too_long',
    label: 'The wait is taking too long',
  );
  static const destinationChange = CancellationReason(
    id: 'destination_change',
    label: 'Destination needs to be changed',
  );
  static const driverNotSuitable = CancellationReason(
    id: 'driver_not_suitable',
    label: 'Driver/ride details are not suitable',
  );
  static const plansChanged = CancellationReason(
    id: 'plans_changed',
    label: 'Plans changed',
  );
  static const somethingElse = CancellationReason(
    id: 'something_else',
    label: 'Something else',
  );

  /// The reasons offered in [phase]. rider-u105: with the codes the
  /// zone's config publishes (`RiderAppConfig.cancelReasons`, admin's
  /// Dispatch › Cancel reasons) only those of this phase are offered, in
  /// the published order; without any that fit, the shipped list.
  static List<CancellationReason> forPhase(
    CancelPhase phase, {
    Iterable<String>? published,
  }) {
    final shipped = _shipped(phase);
    if (published == null) return shipped;
    final byId = {for (final reason in shipped) reason.id: reason};
    final offered = <CancellationReason>[
      for (final code in published.toSet())
        if (byId[code] != null) byId[code]!,
    ];
    return offered.isEmpty ? shipped : offered;
  }

  static List<CancellationReason> _shipped(CancelPhase phase) {
    switch (phase) {
      case CancelPhase.searching:
        return const [
          pickupIncorrect,
          wrongRideOption,
          requestedByMistake,
          waitTooLong,
          destinationChange,
          plansChanged,
          somethingElse,
        ];
      case CancelPhase.matched:
        return const [
          pickupIncorrect,
          destinationChange,
          driverNotSuitable,
          plansChanged,
          somethingElse,
        ];
      case CancelPhase.inTrip:
        return const [
          destinationChange,
          driverNotSuitable,
          plansChanged,
          somethingElse,
        ];
      case CancelPhase.reservation:
        return const [
          plansChanged,
          requestedByMistake,
          pickupIncorrect,
          destinationChange,
          somethingElse,
        ];
    }
  }
}

class CancelOutcome {
  const CancelOutcome._({
    required this.cancelled,
    this.reasonId,
    this.changeDestination = false,
  });

  const CancelOutcome.keep() : this._(cancelled: false);
  const CancelOutcome.cancel({String? reasonId})
    : this._(cancelled: true, reasonId: reasonId);

  /// Q2: the rider took "Change destination instead?": the ride is kept and
  /// the caller opens the route-change flow.
  const CancelOutcome.changeDestination()
    : this._(cancelled: false, changeDestination: true);

  final bool cancelled;
  final String? reasonId;
  final bool changeDestination;
}
