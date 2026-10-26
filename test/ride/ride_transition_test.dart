import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_transition.dart';

void main() {
  test('happy path booking transitions', () {
    var status = RideStatus.idle;
    status = transitionRide(status, RideStatus.pickupSelected);
    status = transitionRide(status, RideStatus.destinationSelected);
    status = transitionRide(status, RideStatus.quoteLoading);
    status = transitionRide(status, RideStatus.rideOptionsReady);
    status = transitionRide(status, RideStatus.rideSelected);
    status = transitionRide(status, RideStatus.paymentSelected);
    status = transitionRide(status, RideStatus.bookingRequested);
    status = transitionRide(status, RideStatus.findingDriver);
    status = transitionRide(status, RideStatus.searchDelayed);
    status = transitionRide(status, RideStatus.findingDriver);
    status = transitionRide(status, RideStatus.driverAssigned);
    status = transitionRide(status, RideStatus.driverArriving);
    status = transitionRide(status, RideStatus.driverWaiting);
    status = transitionRide(status, RideStatus.tripStarted);
    status = transitionRide(status, RideStatus.tripInProgress);
    status = transitionRide(status, RideStatus.tripCompleted);
    status = transitionRide(status, RideStatus.paymentProcessing);
    status = transitionRide(status, RideStatus.paymentFinalized);
    status = transitionRide(status, RideStatus.ratingPending);
    status = transitionRide(status, RideStatus.closed);
    expect(status, RideStatus.closed);
  });

  test('rider cancellation is valid throughout an active trip', () {
    for (final status in [
      RideStatus.tripStarted,
      RideStatus.tripInProgress,
      RideStatus.approachingDropoff,
    ]) {
      expect(canTransition(status, RideStatus.cancelledByRider), isTrue);
    }
  });

  test('rejects illegal jumps', () {
    expect(
      () => transitionRide(RideStatus.idle, RideStatus.findingDriver),
      throwsA(isA<InvalidRideTransition>()),
    );
  });

  test('terminal states cannot move', () {
    for (final terminal in [
      RideStatus.closed,
      RideStatus.cancelledByRider,
      RideStatus.cancelledByDriver,
      RideStatus.cancelledBySystem,
      RideStatus.noDriverFound,
      RideStatus.paymentFailed,
      RideStatus.bookingExpired,
    ]) {
      expect(
        () => transitionRide(terminal, RideStatus.idle),
        throwsA(isA<InvalidRideTransition>()),
      );
    }
  });

  test('restoreFromBackend may jump; apply stays on the graph', () {
    final session = RideSession();
    expect(canTransition(RideStatus.idle, RideStatus.driverArriving), isFalse);

    session.restoreFromBackend(RideStatus.driverArriving, id: 'trip-restore-1');
    expect(session.status, RideStatus.driverArriving);
    expect(session.rideId, 'trip-restore-1');

    expect(
      () => session.apply(RideStatus.idle),
      throwsA(isA<InvalidRideTransition>()),
    );
  });
}
