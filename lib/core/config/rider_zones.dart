/// The zones the Rider has a config document for, and which one a pickup
/// is in. Q7 (owner decision): the pickup location decides the zone, and
/// the zone decides the currency.
///
/// The zone ids, currencies and time zones are Admin's (`markets.ts`:
/// Z001 Norrmalm in Sweden, FR-PC Paris Centre, TN-TC Tunis Centre). There
/// is no zone geometry on the wire yet (contract v0.3.0 has none), so a
/// pickup is placed by country: anywhere in Sweden is Z001, in mainland
/// France FR-PC, in Tunisia TN-TC. A pickup in none of them stays in the
/// home zone, Z001, as before.
class RiderZone {
  const RiderZone({
    required this.id,
    required this.currency,
    required this.timeZone,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final String id;

  /// ISO-4217 code of every price in the zone.
  final String currency;
  final String timeZone;

  /// The country's bounding box, in degrees.
  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(double lat, double lng) =>
      lat >= south && lat <= north && lng >= west && lng <= east;
}

abstract final class RiderZones {
  static const sweden = RiderZone(
    id: 'Z001',
    currency: 'SEK',
    timeZone: 'Europe/Stockholm',
    south: 55.0,
    west: 10.5,
    north: 69.2,
    east: 24.3,
  );

  static const france = RiderZone(
    id: 'FR-PC',
    currency: 'EUR',
    timeZone: 'Europe/Paris',
    south: 41.3,
    west: -5.3,
    north: 51.2,
    east: 9.7,
  );

  static const tunisia = RiderZone(
    id: 'TN-TC',
    currency: 'TND',
    timeZone: 'Africa/Tunis',
    south: 30.2,
    west: 7.5,
    north: 37.6,
    east: 11.7,
  );

  /// The home zone: the one a pickup outside every known zone gets.
  static const home = sweden;

  static const all = <RiderZone>[sweden, france, tunisia];

  /// The zone of a pickup at [lat], [lng]. Never null: unknown places and a
  /// missing point are the home zone.
  static RiderZone at(double? lat, double? lng) {
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return home;
    }
    for (final zone in all) {
      if (zone.contains(lat, lng)) return zone;
    }
    return home;
  }

  /// The zone with [id], or null.
  static RiderZone? byId(String? id) {
    for (final zone in all) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  /// The zone whose prices are in [currency], or null.
  static RiderZone? byCurrency(String? currency) {
    for (final zone in all) {
      if (zone.currency == currency) return zone;
    }
    return null;
  }
}
