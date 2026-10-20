import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/ride_booking/data/driver_repository.dart';
import 'package:movera_rider/features/ride_complete/data/ride_complete_repository.dart';
import 'package:movera_rider/features/ride_complete/data/ride_dispute_repository.dart';
import 'package:movera_rider/features/ride_complete/data/ride_feedback_repository.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';

class RideCompleteController {
  RideCompleteController({
    ActiveRideController? ride,
    DriverRepository? drivers,
    TripReceiptRepository? trips,
    TipCatalog? tips,
    RideDisputeRepository? disputes,
    RideFeedbackRepository? feedback,
  }) : _ride = ride ?? ActiveRideController(),
       _drivers = drivers ?? const DriverRepository(),
       _trips = trips ?? const TripReceiptRepository(),
       _tips = tips ?? const TipCatalog(),
       _disputes = disputes ?? RideDisputeRepository(),
       _feedback = feedback ?? RideFeedbackRepository();

  final ActiveRideController _ride;
  final DriverRepository _drivers;
  final TripReceiptRepository _trips;
  final TipCatalog _tips;
  final RideDisputeRepository _disputes;
  final RideFeedbackRepository _feedback;

  void close() => _ride.markClosed();
  Future<void> closeCompletedRide(String rideId) => _ride.closeCompletedRide(rideId);
  Future<void> submitFeedback({
    required String rideId,
    double? rating,
    int? tipMinor,
    required String idempotencyKey,
  }) => _feedback.submit(
    rideId: rideId,
    rating: rating,
    tipMinor: tipMinor,
    idempotencyKey: idempotencyKey,
  );
  Future<void> persistCompletedStatus(RideStatus status, {required String rideId}) =>
      _ride.persistCompletedStatus(status, rideId: rideId);
  DriverProfile? driver() => _drivers.current();
  TripReceipt? receipt() => _trips.last();
  /// The tip options are kronor amounts ([TipCatalog]). A trip in another
  /// currency (Q7) offers none until its amounts are agreed.
  List<String> tips() {
    final currency = LastCompletedRide.value?.currency ?? Money.defaultCurrency;
    return currency == Money.defaultCurrency ? _tips.amounts() : const [];
  }

  Future<void> submitDispute({
    required String rideId,
    required String reason,
    String? detail,
  }) => _disputes.submit(rideId: rideId, reason: reason, detail: detail);
}
