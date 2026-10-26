import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
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
    RiderConfigRepository? config,
    this.tipsOnServer = true,
  }) : _config = config,
       _ride = ride ?? ActiveRideController(),
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
  final RiderConfigRepository? _config;

  /// False against movera-server, which has no tips yet
  /// (`tips_not_available`): the screen then offers none (its honest
  /// "Tips unavailable" state) instead of amounts that are never sent.
  final bool tipsOnServer;

  void close() => _ride.markClosed();
  Future<void> closeCompletedRide(String rideId) =>
      _ride.closeCompletedRide(rideId);
  Future<void> submitFeedback({
    required String rideId,
    double? rating,
    int? tipMinor,
    required String idempotencyKey,
  }) => _feedback.submit(
    rideId: rideId,
    rating: rating,
    tipMinor: tipMinor,
    // Q5: the tip is in the trip's own currency, never assumed kronor.
    tipCurrency: _tripCurrency(rideId),
    idempotencyKey: idempotencyKey,
  );
  Future<void> chargeCompletedWallet(String rideId) =>
      _ride.chargeCompletedWallet(rideId);
  Future<void> markCompletedPaymentFailed(String rideId) =>
      _ride.markCompletedPaymentFailed(rideId);
  Future<void> markPaymentRetried(String rideId, RideStatus status) =>
      _ride.markPaymentRetried(rideId, status);
  Future<void> persistCompletedStatus(
    RideStatus status, {
    required String rideId,
  }) => _ride.persistCompletedStatus(status, rideId: rideId);
  // rider-u166: [rideId] is the ride the completion screen shows; another
  // ride remembered in LastCompletedRide is never shown for it.
  DriverProfile? driver({String? rideId}) => _drivers.current(rideId: rideId);
  TripReceipt? receipt({String? rideId}) => _trips.last(rideId: rideId);
  String _tripCurrency(String? rideId) =>
      LastCompletedRide.forRide(rideId)?.currency ?? Money.defaultCurrency;

  /// The tip options to show before the zone's config is read: the fixed
  /// catalog when one was given, else the built-in seed of the trip's
  /// currency (owner Q5: 10/20/30 kr, 1/2/5 €, 1/2/3 DT).
  List<Money> initialTips({String? rideId}) => !tipsOnServer
      ? const <Money>[]
      : _tips.fixed ??
            seedConfigForTrip(_tripCurrency(rideId))?.enabledTips ??
            const <Money>[];

  /// The tip options of the trip's zone (Q5): its enabled `tips`, in its
  /// currency. Falls back to [initialTips] when no config of that currency
  /// can be read.
  Future<List<Money>> tips({String? rideId}) async {
    if (!tipsOnServer) return const <Money>[];
    final fixed = _tips.fixed;
    if (fixed != null) return fixed;
    final ride = LastCompletedRide.forRide(rideId);
    final config = await (_config ?? AppScope.instance.riderConfig).forTrip(
      currency: _tripCurrency(rideId),
      pickupLat: ride?.pickupLat,
      pickupLng: ride?.pickupLng,
    );
    return config?.enabledTips ?? initialTips(rideId: rideId);
  }

  Future<void> submitDispute({
    required String rideId,
    required String reason,
    String? detail,
  }) => _disputes.submit(rideId: rideId, reason: reason, detail: detail);
}
