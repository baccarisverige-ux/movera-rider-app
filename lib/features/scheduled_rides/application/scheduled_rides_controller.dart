import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';

class ScheduledRideSession {
  String pickup = 'Current location';
  String dropoff = '';
  List<String> stops = [];
  double? pickupLat;
  double? pickupLng;
  DateTime? scheduledAt;
  String timezone = 'Europe/Stockholm';
  String note = '';
  String paymentMethod = 'Wallet';
  String rideType = 'economy';
  String? quoteId;
  String? bookingId;
  String submissionStatus = 'idle';

  void captureRoute({
    required String pickup,
    required String dropoff,
    required List<String> stops,
  }) {
    this.pickup = pickup;
    this.dropoff = dropoff;
    this.stops = List<String>.from(stops);
  }

  void capturePickupPoint(double lat, double lng, {String? address}) {
    pickupLat = lat;
    pickupLng = lng;
    if (address != null && address.trim().isNotEmpty) pickup = address.trim();
  }

  void captureSchedule(DateTime at, {String timezone = 'Europe/Stockholm'}) {
    scheduledAt = PickupSchedule(timezone).clampPickup(at);
    this.timezone = timezone;
  }

  /// Q9, owner decision 9: the wall-clock pickup in the pickup zone
  /// [timezone], sent as its UTC instant (contract: `scheduledAt` RFC 3339
  /// UTC), whatever the phone's own time zone.
  String? get scheduledAtWire => switch (scheduledAt) {
    final at? => WireTime.format(PickupSchedule(timezone).toUtc(at)),
    null => null,
  };

  void captureNote(String value) {
    note = value;
  }

  void capturePayment(String method) {
    paymentMethod = method;
  }

  void captureRideType(String type, {String? quoteId}) {
    rideType = type;
    this.quoteId = quoteId ?? this.quoteId;
  }

  Future<String> confirm({Future<String> Function()? book}) async {
    submissionStatus = 'submitting';
    bookingId =
        await (book ??
            () => AppScope.instance.booking.requestBooking(
              rideType: rideType,
              paymentMethod: paymentMethod,
              scheduledAt: scheduledAtWire,
              // RIDE-22: the route is part of the booking and its key.
              pickupAddress: pickup,
              pickupLat: pickupLat,
              pickupLng: pickupLng,
              destinationAddress: dropoff,
            ))();
    submissionStatus = 'confirmed';
    return bookingId!;
  }
}
