import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/payments/domain/payment_status.dart';
import 'package:movera_rider/features/ratings/domain/rating_status.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/trips/domain/ride_status_adapter.dart';
import 'package:movera_rider/features/trips/domain/trip_status.dart';

void main() {
  test('RideStatus projects onto separate trip/payment/rating dimensions', () {
    expect(RideStatus.findingDriver.tripStatus, TripStatus.searching);
    expect(RideStatus.paymentProcessing.tripStatus, TripStatus.completed);
    expect(
      RideStatus.paymentProcessing.paymentStatus,
      PaymentStatus.processing,
    );
    expect(RideStatus.ratingPending.ratingStatus, RatingStatus.pending);
  });

  test('RideSession keeps canonical dimensions synchronized', () {
    final session = RideSession();
    session.restoreFromBackend(RideStatus.driverArriving, id: 'ride-1');

    expect(session.tripStatus, TripStatus.driverToPickup);
    expect(session.paymentStatus, PaymentStatus.notStarted);
    expect(session.ratingStatus, RatingStatus.notRequested);

    session.restoreFromBackend(RideStatus.paymentFinalized, id: 'ride-1');
    expect(session.tripStatus, TripStatus.completed);
    expect(session.paymentStatus, PaymentStatus.succeeded);
  });

  test('completed trip status is independent from payment failure', () {
    expect(RideStatus.paymentFailed.tripStatus, TripStatus.completed);
    expect(RideStatus.paymentFailed.paymentStatus, PaymentStatus.failed);
  });
}
