import 'package:movera_rider/core/contracts/server_clock.dart';

/// Server-owned fare quote. The app displays it; it does not invent prices.
class RideQuote {
  const RideQuote({
    required this.id,
    required this.rideType,
    required this.totalMinor,
    required this.currency,
    required this.expiresAt,
    this.baseMinor = 0,
    this.distanceMinor = 0,
    this.timeMinor = 0,
    this.bookingFeeMinor = 0,
    this.surgeMinor = 0,
    this.discountMinor = 0,
    this.signedPayload,
  });

  final String id;
  final String rideType;
  final int totalMinor;
  final String currency;
  final DateTime expiresAt;
  final int baseMinor;
  final int distanceMinor;
  final int timeMinor;
  final int bookingFeeMinor;
  final int surgeMinor;
  final int discountMinor;
  final String? signedPayload;

  /// rider-r4-32: [expiresAt] is server time, judged on the server clock.
  bool get expired => ServerClock.now().isAfter(expiresAt);
}
