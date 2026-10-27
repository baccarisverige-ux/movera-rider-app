class RideCatalogItem {
  const RideCatalogItem({
    required this.id,
    required this.image,
    required this.name,
    required this.note,
    required this.arrival,
    required this.etaMin,
    required this.price,
    required this.seats,
    this.badge,
    this.glyph,
    this.currency = 'SEK',
    this.line,
  });

  final String id;
  final String image;
  final String name;
  final String note;
  final String arrival;
  final int etaMin;

  /// The list price in whole units of [currency].
  final double price;

  /// ISO-4217 code of [price]. The list is not per zone: a pickup in a
  /// zone with another currency shows the quote, never this price.
  final String currency;
  final int seats;
  final String? badge;
  final String? glyph;

  /// Contract v0.7.1: the sub-line the admin wrote under the car type's
  /// name, per app language (`catalog.categories[].line { sv, fr, en }`);
  /// null when the catalog has none (the built-in [note] is shown).
  final Map<String, String>? line;

  /// The sub-line in [languageCode], else null.
  String? lineIn(String languageCode) {
    final text = line?[languageCode]?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class RidePaymentItem {
  const RidePaymentItem({
    required this.brand,
    required this.name,
    required this.detail,
  });

  final String brand;
  final String name;
  final String detail;
}
