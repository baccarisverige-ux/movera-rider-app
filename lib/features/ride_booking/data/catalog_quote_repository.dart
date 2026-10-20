import 'package:movera_rider/core/api/mock_catalog_fares.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

/// Dev fallback only. Live Select Ride must go through [ApiQuoteRepository].
class CatalogQuoteRepository implements QuoteRepository {
  static const pricesKr = mockCatalogPricesKr;

  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) async {
    final kr = pricesKr[rideType] ?? 259;
    // Q7: the pickup's zone decides the currency (the list price in it).
    final zone = RiderZones.at(pickupPoint?.latitude, pickupPoint?.longitude);
    final list = MockZoneRates(
      catalogKronor: kr,
      currency: zone.currency,
    ).listMinor;
    return RideQuote(
      id: 'q_fallback_$rideType',
      rideType: rideType,
      totalMinor: list,
      currency: zone.currency,
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      baseMinor: list,
      signedPayload: 'fallback',
    );
  }
}
