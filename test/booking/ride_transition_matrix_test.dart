import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_transition.dart';

void main() {
  const allowed = <RideStatus, Set<RideStatus>>{
    RideStatus.idle: {RideStatus.pickupSelected},
    RideStatus.pickupSelected: {
      RideStatus.destinationSelected,
      RideStatus.idle,
    },
    RideStatus.destinationSelected: {
      RideStatus.quoteLoading,
      RideStatus.pickupSelected,
      RideStatus.idle,
    },
    RideStatus.quoteLoading: {
      RideStatus.rideOptionsReady,
      RideStatus.idle,
      RideStatus.bookingExpired,
    },
    RideStatus.rideOptionsReady: {
      RideStatus.rideSelected,
      RideStatus.quoteLoading,
      RideStatus.idle,
    },
    RideStatus.rideSelected: {
      RideStatus.paymentSelected,
      RideStatus.rideOptionsReady,
    },
    RideStatus.paymentSelected: {
      RideStatus.bookingRequested,
      RideStatus.rideSelected,
    },
    RideStatus.bookingRequested: {
      RideStatus.findingDriver,
      RideStatus.bookingExpired,
      RideStatus.cancelledByRider,
      RideStatus.cancelledBySystem,
      RideStatus.cancelledByAdmin,
      RideStatus.tripFailed,
    },
    RideStatus.findingDriver: {
      RideStatus.searchDelayed,
      RideStatus.driverAssigned,
      RideStatus.noDriverFound,
      RideStatus.cancelledByRider,
      RideStatus.cancelledBySystem,
      RideStatus.cancelledByAdmin,
      RideStatus.tripFailed,
    },
    RideStatus.searchDelayed: {
      RideStatus.findingDriver,
      RideStatus.driverAssigned,
      RideStatus.noDriverFound,
      RideStatus.cancelledByRider,
      RideStatus.cancelledBySystem,
      RideStatus.cancelledByAdmin,
      RideStatus.tripFailed,
    },
    RideStatus.driverAssigned: {
      RideStatus.driverArriving,
      RideStatus.cancelledByRider,
      RideStatus.cancelledByDriver,
      RideStatus.cancelledBySystem,
      RideStatus.cancelledByAdmin,
      RideStatus.tripFailed,
      RideStatus.noShow,
    },
    RideStatus.driverArriving: {
      RideStatus.driverWaiting,
      RideStatus.cancelledByRider,
      RideStatus.cancelledByDriver,
      RideStatus.cancelledByAdmin,
      RideStatus.cancelledBySystem,
      RideStatus.tripFailed,
      RideStatus.noShow,
    },
    RideStatus.driverWaiting: {
      RideStatus.tripStarted,
      RideStatus.cancelledByRider,
      RideStatus.cancelledByDriver,
      RideStatus.cancelledByAdmin,
      RideStatus.tripFailed,
      RideStatus.noShow,
    },
    RideStatus.tripStarted: {
      RideStatus.tripInProgress,
      RideStatus.cancelledByRider,
      RideStatus.cancelledByAdmin,
      RideStatus.tripFailed,
      RideStatus.endedByDriver,
      RideStatus.tripCompleted,
    },
    RideStatus.tripInProgress: {
      RideStatus.approachingDropoff,
      RideStatus.tripCompleted,
      RideStatus.cancelledByRider,
      RideStatus.cancelledBySystem,
      RideStatus.cancelledByAdmin,
      RideStatus.tripFailed,
      RideStatus.endedByDriver,
    },
    RideStatus.approachingDropoff: {
      RideStatus.tripCompleted,
      RideStatus.cancelledByRider,
      RideStatus.cancelledBySystem,
      RideStatus.cancelledByAdmin,
      RideStatus.tripFailed,
      RideStatus.endedByDriver,
    },
    RideStatus.tripCompleted: {
      RideStatus.paymentProcessing,
      RideStatus.paymentFailed,
      RideStatus.closed,
    },
    RideStatus.paymentProcessing: {
      RideStatus.paymentFinalized,
      RideStatus.paymentFailed,
      RideStatus.closed,
    },
    RideStatus.paymentFinalized: {RideStatus.ratingPending, RideStatus.closed},
    RideStatus.ratingPending: {RideStatus.closed},
  };

  test(
    'every allowed ride transition succeeds and every inverse/illegal transition fails',
    () {
      var allowedCount = 0;
      var rejectedCount = 0;

      for (final from in RideStatus.values) {
        for (final to in RideStatus.values) {
          final shouldPass =
              !from.isTerminal && (allowed[from]?.contains(to) ?? false);
          if (shouldPass) {
            expect(
              transitionRide(from, to),
              to,
              reason: 'expected ${from.name} -> ${to.name} to be legal',
            );
            allowedCount += 1;
          } else {
            expect(
              () => transitionRide(from, to),
              throwsA(isA<InvalidRideTransition>()),
              reason: 'expected ${from.name} -> ${to.name} to be rejected',
            );
            rejectedCount += 1;
          }
        }
      }

      expect(allowedCount, greaterThan(0));
      expect(rejectedCount, greaterThan(allowedCount));
    },
  );

  test('all terminal states are immutable', () {
    final terminal = RideStatus.values.where((status) => status.isTerminal);
    expect(terminal.toSet(), {
      RideStatus.closed,
      RideStatus.cancelledByRider,
      RideStatus.cancelledByDriver,
      RideStatus.cancelledBySystem,
      RideStatus.noDriverFound,
      RideStatus.paymentFailed,
      RideStatus.bookingExpired,
      // Contract v0.3.0: distinct terminal causes.
      RideStatus.cancelledByAdmin,
      RideStatus.noShow,
      RideStatus.tripFailed,
      RideStatus.endedByDriver,
    });

    for (final from in terminal) {
      for (final to in RideStatus.values) {
        expect(
          () => transitionRide(from, to),
          throwsA(isA<InvalidRideTransition>()),
          reason: 'terminal ${from.name} must not transition to ${to.name}',
        );
      }
    }
  });

  test('searching, matched and completion classifications are exact', () {
    expect(RideStatus.values.where((status) => status.isSearching).toSet(), {
      RideStatus.bookingRequested,
      RideStatus.findingDriver,
      RideStatus.searchDelayed,
    });
    expect(RideStatus.values.where((status) => status.isMatched).toSet(), {
      RideStatus.driverAssigned,
      RideStatus.driverArriving,
      RideStatus.driverWaiting,
      RideStatus.tripStarted,
      RideStatus.tripInProgress,
      RideStatus.approachingDropoff,
    });
    expect(
      RideStatus.values.where((status) => status.isCompletedSurface).toSet(),
      {
        RideStatus.tripCompleted,
        RideStatus.paymentProcessing,
        RideStatus.paymentFinalized,
        RideStatus.ratingPending,
      },
    );
  });
}
