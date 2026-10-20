import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/shared/formatters/money.dart';

class DriverProfile {
  const DriverProfile({
    required this.name,
    required this.tagline,
    required this.vehicle,
    required this.plate,
    required this.rideNumber,
    required this.ratingLabel,
    required this.completedAt,
    this.vehicleImage = 'assets/images/comfort_ride.webp',
    this.photoAsset = 'assets/images/profile_img.webp',
  });

  final String name;
  final String tagline;
  final String vehicle;
  final String plate;
  final String rideNumber;
  final String ratingLabel;
  final String completedAt;
  final String vehicleImage;
  final String photoAsset;
}

class DriverRepository {
  const DriverRepository({DriverProfile? current}) : _current = current;

  final DriverProfile? _current;

  /// The driver of the ride just completed. Explicitly-passed profiles win, so
  /// tests and callers with their own driver keep working unchanged.
  DriverProfile? current() {
    final injected = _current;
    if (injected != null) return injected;

    final ride = LastCompletedRide.value;
    final driver = ride?.driver;
    if (ride == null || driver == null) return null;

    final vehicle = [
      driver.vehicleColor,
      driver.vehicleMake,
      driver.vehicleModel,
    ].where((part) => part != null && part.isNotEmpty).join(' ');

    return DriverProfile(
      name: driver.firstName,
      tagline: driver.tripCount == null
          ? 'Movera driver'
          : '${driver.tripCount} trips completed',
      vehicle: vehicle.isEmpty ? 'Vehicle details unavailable' : vehicle,
      plate: driver.plate ?? '',
      rideNumber: ride.rideId ?? '',
      ratingLabel: driver.rating?.toStringAsFixed(1) ?? '',
      completedAt: _completedAtLabel(ride.savedAt),
    );
  }

  static String _completedAtLabel(DateTime when) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    return '${when.day} ${months[when.month - 1]} ${when.year}, $hh:$mm';
  }
}

class TripReceipt {
  const TripReceipt({
    required this.pickup,
    required this.destination,
    required this.total,
    required this.method,
    this.isFinal = true,
    this.endedEarly = false,
    this.drivenMeters,
  });

  final String pickup;
  final String destination;
  final String total;
  final String method;
  final bool isFinal;

  /// R-O6: the rider ended the trip on board; [total] is what they pay for
  /// the distance driven.
  final bool endedEarly;

  /// R-O1: the distance driven, when known.
  final int? drivenMeters;
}

class TripReceiptRepository {
  const TripReceiptRepository({TripReceipt? receipt}) : _receipt = receipt;

  final TripReceipt? _receipt;

  /// The receipt for the ride just completed, in SEK. Null when no ride has
  /// finished, so the screen keeps its honest empty state.
  TripReceipt? last() {
    final injected = _receipt;
    if (injected != null) return injected;

    final ride = LastCompletedRide.value;
    if (ride == null) return null;

    final charged = LastCompletedRide.charged;
    return TripReceipt(
      pickup: ride.pickupAddress,
      destination: ride.destinationAddress,
      total: charged != null ? formatMoney(charged) : formatKr(ride.price),
      method: ride.paymentMethod,
      // The local completion snapshot only knows the booked/quoted amount,
      // unless the server already said what the rider pays (end-early).
      isFinal: charged != null,
      endedEarly: LastCompletedRide.endedEarly,
      drivenMeters: LastCompletedRide.drivenMeters,
    );
  }
}
