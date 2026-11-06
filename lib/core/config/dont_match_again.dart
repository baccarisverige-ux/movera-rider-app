/// Fix job 10 (contract v0.18.43 §64, `contract.json#blockedPairs`; owner
/// G16 Q16-4, G15 2026-11-05 "Never told", "No, only Support"): the served
/// RiderAppConfig.dontMatchAgain `{ on, atStars }` (written by the server
/// from the zone's CountryRules). The rating shows the tick "Don't match me
/// with this driver again" only at [atStars] stars or fewer while [on].
/// The app never shows a block and has no undo.
class DontMatchAgain {
  const DontMatchAgain({required this.on, required this.atStars});

  /// `contract.json#configDefaults.dontMatchAgain`.
  static const DontMatchAgain defaults = DontMatchAgain(on: true, atStars: 1);

  /// The last served value, else the defaults.
  static DontMatchAgain current = defaults;

  final bool on;
  final int atStars;

  bool offeredAt(double stars) => on && stars >= 1 && stars.round() <= atStars;

  static DontMatchAgain fromJson(Object? json) {
    if (json is! Map) return defaults;
    final on = json['on'];
    final stars = json['atStars'];
    return DontMatchAgain(
      on: on is bool ? on : defaults.on,
      atStars: stars is int && stars >= 1 && stars <= 2
          ? stars
          : defaults.atStars,
    );
  }
}
