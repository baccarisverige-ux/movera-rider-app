import 'package:movera_rider/core/contracts/money.dart';

/// Dev fallback fares in whole kronor, shared by the in-process mock server
/// and the catalog fallback quote repository. Lives in core so the mock
/// transport does not import a feature (ARCH-17).
const mockCatalogPricesKr = <String, int>{
  'economy': 259,
  'comfort': 339,
  'premium': 369,
  'priority': 289,
  'xl': 399,
  'electric': 259,
  'pet': 279,
};

/// The stand-in quote engine's rates for one category, in whole major units
/// of the zone currency. One table for quotes, route changes and end-early
/// (R-O1), so they never price the same kilometre differently.
///
/// A category's list price ([catalogMajor]) covers a trip of
/// [includedMeters]; the fare then moves [perKmMajor] per kilometre either
/// way, never below 60% of the list price. Written as a base fare plus a
/// per-km rate that is `base = list price − 3 km × per-km rate`.
class MockCategoryRates {
  const MockCategoryRates({required this.catalogMajor});

  /// The list price covers a trip this long.
  static const includedMeters = 3000;

  /// The per-kilometre rate. The stand-in uses one rate for every
  /// category; categories differ by their list price, so by base fare.
  static const perKmMajor = 12;

  /// The category's list price (`GET /ride-types` → `price`).
  final int catalogMajor;

  /// What a trip of no distance costs: the list price less the kilometres
  /// it already covers.
  int get baseMajor => catalogMajor - includedMeters * perKmMajor ~/ 1000;

  /// A quote for [meters] in whole major units (unchanged quote formula).
  int quoteMajor(int meters) {
    final extraKm = (meters - includedMeters) / 1000;
    final major = (catalogMajor + extraKm * perKmMajor).round();
    final minimum = (catalogMajor * 0.6).round();
    return major < minimum ? minimum : major;
  }

  /// The base fare as Money, with [currency]'s ISO exponent.
  Money baseFare(String currency) =>
      Money(baseMajor * _unit(currency), currency);

  /// [meters] × the per-km rate as Money, rounded half-up to a whole minor
  /// unit with [currency]'s ISO exponent.
  Money distanceFare(int meters, String currency) {
    final scaled = (meters < 0 ? 0 : meters) * perKmMajor * _unit(currency);
    return Money((scaled + 500) ~/ 1000, currency);
  }

  static int _unit(String currency) {
    var unit = 1;
    for (var i = 0; i < Money.exponentOf(currency); i++) {
      unit *= 10;
    }
    return unit;
  }
}
