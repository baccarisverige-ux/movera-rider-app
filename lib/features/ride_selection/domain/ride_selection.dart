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
