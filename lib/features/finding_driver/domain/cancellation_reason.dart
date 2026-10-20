enum CancelPhase { searching, matched, inTrip, reservation }

class CancellationReason {
  const CancellationReason({required this.id, required this.label});

  final String id;
  final String label;

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

  static List<CancellationReason> forPhase(CancelPhase phase) {
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
