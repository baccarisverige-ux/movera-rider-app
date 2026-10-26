import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_selection/domain/nearby_car.dart';

/// `GET /rider/nearby-vehicles?lat&lng` (contract v0.5.2 §13).
class NearbyCarsRepository implements NearbyCarsSource {
  NearbyCarsRepository(this._api);

  final ApiClient _api;

  /// Without a `refreshSeconds` from the server: the contract's 5 s with a
  /// little slack for a small server instance.
  static const defaultRefresh = Duration(seconds: 6);

  /// The app never asks more often than this, whatever the server says:
  /// the cars are decoration, the trip calls come first on a slow server.
  static const minRefresh = Duration(seconds: 5);
  static const maxRefresh = Duration(seconds: 30);

  /// The contract's cap; a longer list is cut.
  static const maxCars = 15;

  @override
  Future<NearbyCarsAnswer> near(GeoPoint point) async {
    final json = await _api.get(
      '/api/v1/rider/nearby-vehicles'
      '?lat=${point.latitude.toStringAsFixed(5)}'
      '&lng=${point.longitude.toStringAsFixed(5)}',
    );
    return parse(json);
  }

  static NearbyCarsAnswer parse(Map<String, dynamic> json) {
    final raw = json['items'];
    final cars = <NearbyCar>[];
    final seen = <String>{};
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final car = NearbyCar.fromJson(Map<String, dynamic>.from(item));
        if (car == null || !seen.add(car.key)) continue;
        cars.add(car);
        if (cars.length == maxCars) break;
      }
    }
    final seconds = json['refreshSeconds'];
    var refresh = seconds is num && seconds.isFinite && seconds > 0
        ? Duration(milliseconds: (seconds * 1000).round())
        : defaultRefresh;
    if (refresh < minRefresh) refresh = minRefresh;
    if (refresh > maxRefresh) refresh = maxRefresh;
    return NearbyCarsAnswer(cars: cars, refresh: refresh);
  }
}
