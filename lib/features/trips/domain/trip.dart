import 'package:movera_rider/features/payments/domain/payment_status.dart';
import 'package:movera_rider/features/ratings/domain/rating_status.dart';
import 'package:movera_rider/features/trips/domain/trip_status.dart';

enum TripCancellationActor { rider, driver, admin, system }

class TripCancellation {
  const TripCancellation({
    required this.actor,
    required this.at,
    this.reasonId,
  });

  final TripCancellationActor actor;
  final String? reasonId;
  final DateTime at;
}

class TripSchedule {
  const TripSchedule({required this.scheduledFor, this.parentTripId});

  final DateTime scheduledFor;
  final String? parentTripId;
}

class Trip {
  const Trip({
    required this.tripId,
    required this.status,
    required this.categoryId,
    required this.paymentMethodId,
    required this.createdAt,
    required this.updatedAt,
    this.version = 0,
    this.schedule,
    this.cancellation,
    this.paymentStatus = PaymentStatus.notStarted,
    this.ratingStatus = RatingStatus.notRequested,
  });

  final String tripId;
  final TripStatus status;
  final String categoryId;
  final String paymentMethodId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final TripSchedule? schedule;
  final TripCancellation? cancellation;
  final PaymentStatus paymentStatus;
  final RatingStatus ratingStatus;

  bool get isScheduled => schedule != null;
}
