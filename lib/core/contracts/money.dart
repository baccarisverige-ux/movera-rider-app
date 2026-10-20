/// Money as the P1 contract carries it: integer minor units (öre) plus an
/// ISO-4217 currency code (ARCH-11, contract C-0).
///
/// Arithmetic and comparison stay in minor units. Whole-kronor doubles exist
/// only at the UI edge ([major]) and for legacy wire fields
/// ([Money.fromLegacyMajor]); new code must not round-trip through them.
class Money {
  const Money(this.amountMinor, [this.currency = defaultCurrency]);

  static const defaultCurrency = 'SEK';

  final int amountMinor;
  final String currency;

  static const zeroSek = Money(0);

  /// A legacy whole-unit amount (`price: 259.0`) converted once, here,
  /// with the currency's ISO exponent (RC-07: 1.5 TND is 1500 millimes,
  /// 1.5 SEK is 150 öre).
  factory Money.fromLegacyMajor(num major, [String currency = defaultCurrency]) {
    final code = normalizeCurrency(currency) ?? defaultCurrency;
    return Money((major * _pow10(exponentOf(code))).round(), code);
  }

  /// Parses `{amountMinor, currency}`. Returns null for anything else,
  /// including a currency that is not a three-letter ISO-4217 code.
  static Money? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final minor = raw['amountMinor'];
    if (minor is! num || minor != minor.roundToDouble()) return null;
    final currency = normalizeCurrency(raw['currency']);
    if (currency == null) return null;
    return Money(minor.toInt(), currency);
  }

  /// An integer minor-units field (`totalMinor: 25900`) in [currency].
  static Money? tryMinor(Object? raw, [Object? currency]) {
    if (raw is! num || raw != raw.roundToDouble()) return null;
    final code = currency == null
        ? defaultCurrency
        : normalizeCurrency(currency);
    if (code == null) return null;
    return Money(raw.toInt(), code);
  }

  /// A legacy whole-unit field (`newPriceKr: 259.5`), when present.
  static Money? tryLegacyMajor(
    Object? raw, [
    String currency = defaultCurrency,
  ]) => raw is num ? Money.fromLegacyMajor(raw, currency) : null;

  /// ISO-4217 minor-unit exponents (`contract.json#currencies`).
  static const exponents = <String, int>{'SEK': 2, 'EUR': 2, 'TND': 3};

  /// Minor units per major unit is `10^exponent`; unknown codes use 2.
  static int exponentOf(String currency) => exponents[currency] ?? 2;

  /// Minor units in one major unit of [currency]: 100 öre, 100 cents,
  /// 1000 millimes.
  static int minorPerMajor(String currency) => _pow10(exponentOf(currency));

  /// Nothing, in [currency].
  const Money.zero(this.currency) : amountMinor = 0;

  /// The contract wire shape, strictly (`fixtures/money.json`): an
  /// integer `amountMinor` and an upper-case ISO-4217 `currency`. A float,
  /// a lower-case code, a missing currency or another key (`minorUnits`)
  /// is not Money.
  static Money? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final minor = raw['amountMinor'];
    final currency = raw['currency'];
    if (minor is! int) return null;
    if (currency is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      return null;
    }
    return Money(minor, currency);
  }

  /// The decimal amount with the currency's exponent: `126.75` SEK,
  /// `12.500` TND, `-20.00` SEK. Display formatting stays local.
  String get majorString {
    final exponent = exponentOf(currency);
    final unit = _pow10(exponent);
    final abs = amountMinor.abs();
    final whole = abs ~/ unit;
    final fraction = (abs % unit).toString().padLeft(exponent, '0');
    final sign = amountMinor < 0 ? '-' : '';
    return exponent == 0 ? '$sign$whole' : '$sign$whole.$fraction';
  }

  static int _pow10(int exponent) {
    var value = 1;
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
    return value;
  }

  /// Upper-cased ISO-4217 alpha code, or null when [raw] is not one.
  static String? normalizeCurrency(Object? raw) {
    if (raw is! String) return null;
    final code = raw.trim().toUpperCase();
    return RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : null;
  }

  /// Major units for display only (`259.0` kr), with the ISO exponent.
  double get major => amountMinor / _pow10(exponentOf(currency));

  bool get isPositive => amountMinor > 0;

  Money operator +(Money other) {
    _sameCurrency(other);
    return Money(amountMinor + other.amountMinor, currency);
  }

  Money operator -(Money other) {
    _sameCurrency(other);
    return Money(amountMinor - other.amountMinor, currency);
  }

  void _sameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Cannot combine $currency and ${other.currency}.');
    }
  }

  Map<String, Object> toJson() => {
    'amountMinor': amountMinor,
    'currency': currency,
  };

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amountMinor == amountMinor &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);

  @override
  String toString() => 'Money($amountMinor $currency)';
}
