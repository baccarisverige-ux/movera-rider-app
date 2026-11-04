part of 'select_ride.dart';

class _RideOption {
  const _RideOption({
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
    this.glyphKey,
    this.currency = Money.defaultCurrency,
  });

  final String id;
  final String image;
  final String name;
  final String note;
  final String arrival;
  final int etaMin;
  final double price;

  /// The list price's currency ([RideCatalogItem.currency]).
  final String currency;
  final int seats;
  final String? badge;
  final IconData? glyph;

  /// The catalog's glyph key ([RidePicture] picks what stands beside the car).
  final String? glyphKey;
}

class _PaymentOption {
  const _PaymentOption({
    required this.brand,
    required this.name,
    required this.detail,
  });

  final String brand;
  final String name;
  final String detail;
}
