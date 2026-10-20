import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

/// Reads a server ride projection (contract C-6, PROPOSED) into the
/// [RideSnapshot] the client restores and archives from (ARCH-12).
///
/// Accepts both the nested proposal (`pickup: {address, lat, lng}`,
/// `totalMinor` + `currency`) and the flat fields the in-process mock sends
/// today (`pickupAddress`, `pickupLat`, `price`). Returns null when a field
/// the ride surfaces cannot do without is missing.
abstract final class RideProjection {
  static RideSnapshot? toSnapshot(Map<String, dynamic> ride, {DateTime? now}) {
    // tripId is canonical; id / rideId are legacy aliases (contract v0.3.0).
    final id = _string(ride['tripId'] ?? ride['id'] ?? ride['rideId']);
    final status = RideStatusWire.fromProjection(ride);
    final pickup = _place(ride, 'pickup');
    final destination = _place(ride, 'destination');
    final fare = _fare(ride);
    final price = fare?.major;
    if (id == null ||
        status == null ||
        pickup == null ||
        destination == null ||
        price == null) {
      return null;
    }
    final rawDriver = ride['driver'];
    final rawCategory = _string(ride['categoryId'] ?? ride['rideType']);
    final categoryId =
        rawCategory == null ? null : CategoryIds.canonical(rawCategory);
    final paymentMethodId = _string(
      ride['paymentMethodId'] ?? ride['paymentMethod'],
    );
    final updatedAt = WireTime.tryParse(ride['updatedAt']);
    final createdAt = WireTime.tryParse(ride['createdAt']);
    final rawNotes = ride['notes'];
    return RideSnapshot(
      rideId: id,
      status: status,
      // The device clock: [RideSnapshot.savedAt] is local bookkeeping and
      // never ordering data (ARCH-1). The server's own time goes to
      // serverUpdatedAt.
      savedAt: now ?? DateTime.now(),
      createdAt: createdAt,
      pickupAddress: pickup.address,
      pickupLat: pickup.latitude,
      pickupLng: pickup.longitude,
      destinationAddress: destination.address,
      destinationLat: destination.latitude,
      destinationLng: destination.longitude,
      stops: _stops(ride['stops']),
      rideType: _string(ride['categoryName']) ?? categoryId ?? 'Movera',
      categoryId: categoryId,
      price: price,
      currency: fare!.currency,
      paymentMethod:
          _string(ride['paymentMethodLabel']) ?? paymentMethodId ?? '',
      paymentMethodId: paymentMethodId,
      walletAmountMinor: _int(ride['walletAmountMinor']) ?? 0,
      maxOfferMinor: _int(ride['maxOfferMinor']),
      driver: rawDriver is Map
          ? MatchedDriver.fromJson(Map<String, dynamic>.from(rawDriver))
          : null,
      notes: rawNotes is Map
          ? RideNotes.fromJson(Map<String, dynamic>.from(rawNotes))
          : RideNotes.empty,
      version: _int(ride['version']),
      serverUpdatedAt: updatedAt,
      searchStartedAt: WireTime.tryParse(ride['searchStartedAt']),
      cancellationReason: _string(ride['cancellationReason']),
    );
  }

  static RouteStop? _place(Map<String, dynamic> ride, String name) {
    final nested = ride[name];
    if (nested is Map) {
      final lat = nested['lat'];
      final lng = nested['lng'];
      if (lat is num && lng is num) {
        return RouteStop(
          address: _string(nested['address']) ?? '',
          latitude: lat.toDouble(),
          longitude: lng.toDouble(),
        );
      }
    }
    final lat = ride['${name}Lat'];
    final lng = ride['${name}Lng'];
    if (lat is! num || lng is! num) return null;
    return RouteStop(
      address: _string(ride['${name}Address']) ?? '',
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
    );
  }

  static List<RouteStop> _stops(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final stop in raw)
        if (stop is Map && stop['lat'] is num && stop['lng'] is num)
          RouteStop(
            address: _string(stop['address']) ?? '',
            latitude: (stop['lat'] as num).toDouble(),
            longitude: (stop['lng'] as num).toDouble(),
          ),
    ];
  }

  /// The trip's fare with its currency (Q7: the pickup's zone): `fare:
  /// Money` first, then `totalMinor` + `currency`, then a `total` Money,
  /// then the legacy whole-unit `price` in the flat `currency` (kronor
  /// when absent).
  static Money? _fare(Map<String, dynamic> ride) {
    // Contract v0.3.0: `fare: Money` is the authoritative fare.
    final fare = Money.fromWire(ride['fare']);
    if (fare != null) return fare;
    final minor = Money.tryMinor(ride['totalMinor'], ride['currency']);
    if (minor != null) return minor;
    final total = Money.fromWire(ride['total']);
    if (total != null) return total;
    final legacy = ride['price'] ?? ride['bookedPrice'];
    if (legacy is! num) return null;
    return Money.fromLegacyMajor(
      legacy,
      Money.normalizeCurrency(ride['currency']) ?? Money.defaultCurrency,
    );
  }

  static String? _string(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  static int? _int(Object? raw) => raw is int
      ? raw
      : raw is num
      ? raw.round()
      : raw is String
      ? int.tryParse(raw)
      : null;
}
