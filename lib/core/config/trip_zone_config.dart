import 'package:movera_rider/core/location/location_repository.dart';

import 'api_rider_config_repository.dart';
import 'rider_app_config.dart';
import 'rider_zones.dart';

/// Which zone's `RiderAppConfig` a trip uses (Q7: the pickup decides the
/// zone, the zone the currency).
///
/// [forTrip] is the document a screen reads its per-zone settings from
/// (tips, raise steps, payment methods, limits). It never mixes money: a
/// document in another currency than the trip's is never used.
extension TripZoneConfig on RiderConfigRepository {
  /// The document of the pickup's zone when it is in [currency], else the
  /// one of the zone that prices in [currency]; null when neither is in
  /// [currency] or none can be read.
  Future<RiderAppConfig?> forTrip({
    required String currency,
    double? pickupLat,
    double? pickupLng,
    bool fresh = false,
  }) async {
    final ids = <String>{
      if (pickupLat != null && pickupLng != null)
        RiderZones.at(pickupLat, pickupLng).id,
      ?RiderZones.byCurrency(currency)?.id,
    };
    for (final id in ids) {
      try {
        // G7 live fix: [fresh] reads the server again first (settings the
        // admin changed since the app started, e.g. routeChange).
        final self = this;
        if (fresh && self is ApiRiderConfigRepository) await self.refresh(id);
        final config = await forZone(id);
        if (config.currency == currency) return config;
      } catch (_) {
        // A zone that cannot be read is skipped; the caller keeps its seed.
      }
    }
    return null;
  }

  /// The document of the zone the point [lat], [lng] is in (the home zone
  /// for an unknown or missing point).
  Future<RiderAppConfig> forPickup(double? lat, double? lng) =>
      forZone(RiderZones.at(lat, lng).id);

  /// Q9: the IANA time zone the pickup zone's config names
  /// (`RiderAppConfig.timeZone`); the built-in zone's when none can be
  /// read. Never throws.
  /// rider-r4-10: the pickup zone's time zone and reservation horizon
  /// (`booking.bookingHorizonDays`), from one document; the zone's
  /// built-in seed when none can be read. Never throws.
  Future<({String timeZone, int horizonDays})> bookingWindowAt(
    double? lat,
    double? lng,
  ) async {
    RiderAppConfig config;
    try {
      config = await forPickup(lat, lng);
    } catch (_) {
      config = SeedRiderConfigRepository.seedFor(RiderZones.at(lat, lng).id);
    }
    return (timeZone: config.timeZone, horizonDays: config.bookingHorizonDays);
  }

  Future<String> timeZoneAt(double? lat, double? lng) async {
    try {
      return (await forPickup(lat, lng)).timeZone;
    } catch (_) {
      return RiderZones.at(lat, lng).timeZone;
    }
  }
}

/// The built-in seed for a trip in [currency], for the first frame before
/// [TripZoneConfig.forTrip] answers. Null for a currency no zone uses.
RiderAppConfig? seedConfigForTrip(String currency) =>
    SeedRiderConfigRepository.seedForCurrency(currency);

/// The zone the rider is in now, for screens with no trip (Wallet,
/// Payment): the zone of the app's last good location fix, else the zone
/// of the last fix this device ever had (sign-out drops the fix, not the
/// zone: rider-r4-41), else the home zone. Never throws.
Future<RiderZone> currentRiderZone({
  LocationRepository location = const LocationRepository(),
}) async {
  try {
    final fix = await location.readLastGoodFix();
    if (fix != null) return RiderZones.at(fix.latitude, fix.longitude);
    return await LocationRepository.readLastZone() ?? RiderZones.home;
  } catch (_) {
    return RiderZones.home;
  }
}
