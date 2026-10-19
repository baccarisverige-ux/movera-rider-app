/// Category ids on the wire (`contract.json#categories`, v0.3.0).
///
/// Ids come from the admin Pricing catalog; the seed ids are the ones every
/// app knows. `movera` is the pre-v0.3 Rider id for `economy` and is
/// accepted on read for one release ([canonical]); the app always writes
/// the canonical id. Labels ("Movera", "Movera XL") are display only.
abstract final class CategoryIds {
  static const economy = 'economy';

  static const seed = <String>[
    'economy',
    'comfort',
    'premium',
    'priority',
    'xl',
    'electric',
    'pet',
  ];

  static const aliases = <String, String>{'movera': economy};

  static final RegExp pattern = RegExp(r'^[a-z][a-z0-9_]{1,31}$');

  /// The canonical id for [raw]: aliases resolved, whitespace trimmed.
  /// Null for anything that is not a category id.
  static String? tryCanonical(Object? raw) {
    if (raw is! String) return null;
    final id = raw.trim();
    final resolved = aliases[id] ?? id;
    return pattern.hasMatch(resolved) ? resolved : null;
  }

  /// [tryCanonical], keeping [raw] as-is when it is not a contract id (an
  /// older label-derived id in device storage).
  static String canonical(String raw) => tryCanonical(raw) ?? raw;
}
