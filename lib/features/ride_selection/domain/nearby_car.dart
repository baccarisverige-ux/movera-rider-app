import 'package:movera_rider/core/maps/geo_point.dart';

/// A free car near the rider (contract v0.5.2 §13): an opaque key that stays
/// the same through the day, a rounded position and the heading when known.
/// Nothing in it tells who drives.
class NearbyCar {
  const NearbyCar({
    required this.key,
    required this.latitude,
    required this.longitude,
    this.heading,
  });

  final String key;
  final double latitude;
  final double longitude;

  /// Degrees clockwise from north, or null when the server did not know.
  final double? heading;

  static NearbyCar? fromJson(Map<String, dynamic> json) {
    final key = json['key'];
    final lat = json['lat'];
    final lng = json['lng'];
    if (key is! String || key.isEmpty || lat is! num || lng is! num) {
      return null;
    }
    final latitude = lat.toDouble();
    final longitude = lng.toDouble();
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    final heading = json['heading'];
    return NearbyCar(
      key: key,
      latitude: latitude,
      longitude: longitude,
      heading: heading is num && heading.isFinite
          ? heading.toDouble() % 360
          : null,
    );
  }
}

/// One answer: the cars and when to ask again.
class NearbyCarsAnswer {
  const NearbyCarsAnswer({required this.cars, required this.refresh});

  final List<NearbyCar> cars;
  final Duration refresh;
}

/// Where the cars come from; the screen's tests hand in their own.
abstract interface class NearbyCarsSource {
  Future<NearbyCarsAnswer> near(GeoPoint point);
}
