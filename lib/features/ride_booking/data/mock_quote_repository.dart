import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

abstract class QuoteRepository {
  /// ARCH-8 / contract C-2: the server prices the trip from [pickupPoint],
  /// [destinationPoint] and [stops], routing it itself. [distanceMeters] and
  /// [durationSeconds] are only a hint; the address strings are labels.
  /// v0.18.163 (contract.json#liveTraffic.rider): no placeholder 600 s any
  /// more; [durationSeconds] is sent only when the app really has one.
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int? durationSeconds,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  });
}
