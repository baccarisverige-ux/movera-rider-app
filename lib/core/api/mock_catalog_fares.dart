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

/// How the stand-in prices a zone whose currency is not the krona: Admin's
/// default prices for the zone (`src/pricing/zonePricing.ts`, `CURRENCY`):
/// a kronor amount times the market's rate, rounded to its price step.
/// Paris: × 0.095, to 0.05 €; Tunis: × 0.3, to 0.1 DT. Stockholm is the
/// kronor table itself, to the krona. The cancel fees in the zones' config
/// documents follow the same rule (35 kr → 3.35 € → 10.5 DT).
class MockZoneCurrency {
  const MockZoneCurrency._(
    this.currency, {
    required this.rateNumerator,
    required this.rateDenominator,
    required this.stepMinor,
  });

  static const sek = MockZoneCurrency._(
    'SEK',
    rateNumerator: 1,
    rateDenominator: 1,
    stepMinor: 100,
  );
  static const eur = MockZoneCurrency._(
    'EUR',
    rateNumerator: 95,
    rateDenominator: 1000,
    stepMinor: 5,
  );
  static const tnd = MockZoneCurrency._(
    'TND',
    rateNumerator: 3,
    rateDenominator: 10,
    stepMinor: 100,
  );

  /// The table for [currency]; an unknown code prices like the krona.
  static MockZoneCurrency of(String currency) => switch (currency) {
    'EUR' => eur,
    'TND' => tnd,
    _ => sek,
  };

  final String currency;
  final int rateNumerator;
  final int rateDenominator;

  /// The price step, in minor units (1 kr, 0.05 €, 0.1 DT).
  final int stepMinor;

  /// [kronor] (whole kr) in this currency's minor units, on the step.
  int fromKronor(num kronor) {
    final unit = Money.minorPerMajor(currency);
    final exact = kronor * rateNumerator * unit / rateDenominator;
    return roundToStep(exact);
  }

  /// [minor] rounded half-up to the price step (never below one step for
  /// a positive amount).
  int roundToStep(num minor) {
    final steps = (minor / stepMinor).round();
    return steps * stepMinor;
  }
}

/// [MockCategoryRates] in a zone's own currency: the kronor rates converted
/// once with [MockZoneCurrency], every result on the zone's price step. In
/// Stockholm it prices exactly like [MockCategoryRates] (same formula, in
/// öre).
class MockZoneRates {
  MockZoneRates({required int catalogKronor, required String currency})
    : _money = MockZoneCurrency.of(currency),
      currency = MockZoneCurrency.of(currency).currency,
      listMinor = MockZoneCurrency.of(currency).fromKronor(catalogKronor),
      perKmMinor = MockZoneCurrency.of(
        currency,
      ).fromKronor(MockCategoryRates.perKmMajor);

  final MockZoneCurrency _money;
  final String currency;

  /// The category's list price, for [MockCategoryRates.includedMeters].
  final int listMinor;
  final int perKmMinor;

  /// A trip of no distance: the list price less the kilometres it covers.
  int get baseMinor =>
      listMinor - MockCategoryRates.includedMeters * perKmMinor ~/ 1000;

  /// A quote for [meters], on the price step, never below 60% of the list
  /// price (the [MockCategoryRates.quoteMajor] formula).
  Money quote(int meters) {
    final extraKm = (meters - MockCategoryRates.includedMeters) / 1000;
    final minor = _money.roundToStep(listMinor + extraKm * perKmMinor);
    final minimum = _money.roundToStep(listMinor * 0.6);
    return Money(minor < minimum ? minimum : minor, currency);
  }

  Money get baseFare => Money(baseMinor, currency);

  /// [meters] × the per-km rate, rounded half-up to a whole minor unit.
  Money distanceFare(int meters) {
    final scaled = (meters < 0 ? 0 : meters) * perKmMinor;
    return Money((scaled + 500) ~/ 1000, currency);
  }

  /// [kronor] in this zone's money, on its step (a stop fee, a cap).
  int convertKronor(num kronor) => _money.fromKronor(kronor);

  /// [minor] on this zone's price step.
  int roundToStep(num minor) => _money.roundToStep(minor);
}
