import 'package:movera_rider/core/contracts/money.dart';

/// One admin-editable amount in the zone's currency: a tip option or a
/// raise-offer quick step (`AmountOption`, CONTRACT.md §6, contract v0.4.0).
class AmountOption {
  const AmountOption({required this.amount, this.enabled = true});

  final Money amount;

  /// A disabled option is kept in the list but not shown.
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is AmountOption &&
      other.amount == amount &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(amount, enabled);

  @override
  String toString() =>
      'AmountOption(${amount.majorString} '
      '${amount.currency}, ${enabled ? 'on' : 'off'})';
}

/// App languages (`languages`, owner Q48/Q49): what the user may pick, and
/// the country's default per app.
class AppLanguages {
  const AppLanguages({
    this.available = ZoneDefaults.languages,
    required this.rider,
    required this.driver,
    required this.admin,
  });

  /// Every app ships these (`contract.json#languages`).
  final List<String> available;
  final String rider;
  final String driver;
  final String admin;

  /// The country's defaults when the document says nothing usable.
  factory AppLanguages.forCountry(String country) {
    final lang = ZoneDefaults.languageOf(country);
    return AppLanguages(rider: lang, driver: lang, admin: lang);
  }

  @override
  bool operator ==(Object other) =>
      other is AppLanguages &&
      other.rider == rider &&
      other.driver == driver &&
      other.admin == admin &&
      other.available.join(',') == available.join(',');

  @override
  int get hashCode => Object.hash(rider, driver, admin, available.join(','));
}

/// `contract.json#configDefaults` (v0.4.0): what the app uses when a config
/// document lacks a per-zone field or has a bad value. A contract test keeps
/// these equal to the contract.
abstract final class ZoneDefaults {
  static const languages = <String>['en', 'fr', 'sv'];

  /// `contract.json#zonePaymentMethods` (owner Q7): every country offers
  /// these four. No Swish, no D17; the wallet is separate.
  static const paymentMethods = <String>[
    'cash',
    'card',
    'apple_pay',
    'google_pay',
  ];

  /// v0.3 ids read as their v0.4 names for one release.
  static const paymentMethodAliases = <String, String>{
    'apple': 'apple_pay',
    'google': 'google_pay',
  };

  static const maxStops = 3;
  static const maxPickupMoveMeters = 200;
  static const freeWaitMin = 5;
  static const freeWaitMinXl = 3;

  /// Country of a zone currency, for documents without `country`.
  static String countryOf(String currency) => switch (currency) {
    'EUR' => 'FR',
    'TND' => 'TN',
    _ => 'SE',
  };

  /// Default app language of [country]: Swedish in Sweden, French in
  /// France and Tunisia, else English.
  static String languageOf(String country) => switch (country) {
    'SE' => 'sv',
    'FR' || 'TN' => 'fr',
    _ => 'en',
  };

  /// The default free wait (= no-show wait, owner Q41) of [categoryId].
  static int freeWaitMinOf(String categoryId) =>
      categoryId == 'xl' ? freeWaitMinXl : freeWaitMin;

  static const _tips = <String, List<int>>{
    'SEK': [1000, 2000, 3000],
    'EUR': [100, 200, 500],
    'TND': [1000, 2000, 3000],
  };

  static const _raiseSteps = <String, List<int>>{
    'SEK': [5000, 10000, 15000, 20000],
    'EUR': [200, 400, 600, 800],
    'TND': [2000, 4000, 6000, 8000],
  };

  /// Tip options in [currency] (owner Q5); empty for an unknown currency.
  static List<AmountOption> tipsIn(String currency) =>
      _options(_tips, currency);

  /// Raise-offer quick steps in [currency] (owner Q6).
  static List<AmountOption> raiseStepsIn(String currency) =>
      _options(_raiseSteps, currency);

  static List<AmountOption> _options(
    Map<String, List<int>> table,
    String currency,
  ) => [
    for (final minor in table[currency] ?? const <int>[])
      AmountOption(amount: Money(minor, currency)),
  ];
}

/// Reads `[{amount: Money, enabled: bool}]` in [currency]. Null when [raw]
/// is not a list or has no valid option (the caller falls back); a bad row
/// (other currency, not positive, a duplicate amount) is skipped and a
/// missing `enabled` reads as on.
List<AmountOption>? readAmountOptions(Object? raw, String currency) {
  if (raw is! List) return null;
  final out = <AmountOption>[];
  for (final row in raw) {
    if (row is! Map) continue;
    final amount = Money.fromWire(row['amount']);
    if (amount == null ||
        amount.currency != currency ||
        amount.amountMinor <= 0 ||
        out.any((option) => option.amount == amount)) {
      continue;
    }
    final enabled = row['enabled'];
    out.add(
      AmountOption(amount: amount, enabled: enabled is bool ? enabled : true),
    );
  }
  return out.isEmpty ? null : out;
}

/// Reads `paymentMethods` as contract zone methods (aliases resolved,
/// unknown ids such as `swish` or `wallet` dropped). Null when [raw] is not
/// a list or names no zone method.
List<String>? readZonePaymentMethods(Object? raw) {
  if (raw is! List) return null;
  final out = <String>[];
  for (final id in raw) {
    if (id is! String) continue;
    final value = ZoneDefaults.paymentMethodAliases[id.trim()] ?? id.trim();
    if (ZoneDefaults.paymentMethods.contains(value) && !out.contains(value)) {
      out.add(value);
    }
  }
  return out.isEmpty ? null : out;
}

/// Reads `languages`; null when it has no valid default for any app.
AppLanguages? readAppLanguages(Object? raw, String country) {
  if (raw is! Map) return null;
  final fallback = AppLanguages.forCountry(country);
  final list = raw['available'];
  final available = <String>[
    if (list is List)
      for (final code in list)
        if (code is String && ZoneDefaults.languages.contains(code)) code,
  ];
  final usable = available.isEmpty
      ? ZoneDefaults.languages
      : available.toSet().toList();
  final defaults = raw['default'];
  String? pick(String app) {
    final value = defaults is Map ? defaults[app] : null;
    return value is String && usable.contains(value) ? value : null;
  }

  final rider = pick('rider');
  final driver = pick('driver');
  final admin = pick('admin');
  if (rider == null && driver == null && admin == null && available.isEmpty) {
    return null;
  }
  String orFallback(String? value, String fallbackValue) =>
      value ?? (usable.contains(fallbackValue) ? fallbackValue : usable.first);
  return AppLanguages(
    available: List.unmodifiable(usable),
    rider: orFallback(rider, fallback.rider),
    driver: orFallback(driver, fallback.driver),
    admin: orFallback(admin, fallback.admin),
  );
}
