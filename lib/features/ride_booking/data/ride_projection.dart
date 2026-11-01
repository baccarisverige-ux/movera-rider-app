import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/raise_limit.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';

/// The display name of a category id (catalog `label`), or null.
typedef CategoryLabel = String? Function(String categoryId);

/// Reads a server ride projection (contract C-6, PROPOSED) into the
/// [RideSnapshot] the client restores and archives from (ARCH-12).
///
/// Accepts the contract shape (`pickup` / `dropoff: Place`, `fare:
/// Money`), the nested proposal (`destination: {address, lat, lng}`,
/// `totalMinor` + `currency`) and the flat fields the in-process mock sends
/// today (`pickupAddress`, `pickupLat`, `price`). Returns null when a field
/// the ride surfaces cannot do without is missing.
abstract final class RideProjection {
  /// [categoryLabel] names the trip's category (rider-r4-7: a contract
  /// trip carries only `categoryId`; labels live in the catalog), then the
  /// built-in catalog, then the id itself.
  static RideSnapshot? toSnapshot(
    Map<String, dynamic> ride, {
    DateTime? now,
    CategoryLabel? categoryLabel,
  }) {
    // tripId is canonical; id / rideId are legacy aliases (contract v0.3.0).
    final id = _string(ride['tripId'] ?? ride['id'] ?? ride['rideId']);
    final status = RideStatusWire.fromProjection(ride);
    final pickup = _place(ride, 'pickup');
    // rider-r4-1: openapi TripProjection names it `dropoff: Place`;
    // `destination` (nested or flat) is the stand-in's legacy shape.
    final destination = _place(ride, 'dropoff') ?? _place(ride, 'destination');
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
    final categoryId = rawCategory == null
        ? null
        : CategoryIds.canonical(rawCategory);
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
      rideType:
          _string(ride['categoryName']) ??
          (categoryId == null
              ? null
              : categoryLabel?.call(categoryId) ??
                    builtInCategoryLabel(categoryId)) ??
          categoryId ??
          'Movera',
      categoryId: categoryId,
      price: price,
      currency: fare!.currency,
      paymentMethod:
          _string(ride['paymentMethodLabel']) ?? paymentMethodId ?? '',
      paymentMethodId: paymentMethodId,
      walletAmountMinor: _int(ride['walletAmountMinor']) ?? 0,
      maxOfferMinor: _int(ride['maxOfferMinor']),
      bookedFareMinor: RaiseLimit.bookedFareMinorOf(ride, fare.currency),
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

  /// The built-in catalog's name for [categoryId], or null.
  static String? builtInCategoryLabel(String categoryId) {
    for (final item in RideSelectionRepository.builtInRides) {
      if (CategoryIds.canonical(item.id) == categoryId) return item.name;
    }
    return null;
  }

  /// rider-u33: the fee the server charged for a cancel (contract §6
  /// `cancellation.fee`, a Money). Null when the cancel was free, the
  /// trip was not cancelled, or the projection has no such field.
  static Money? cancellationFee(Map<String, dynamic> ride) {
    final cancellation = ride['cancellation'];
    if (cancellation is! Map) return null;
    final fee = Money.fromWire(cancellation['fee']);
    return fee != null && fee.isPositive ? fee : null;
  }

  /// G6 (contract v0.18.8 §34, round 1): a reversed no-show.
  /// `cancellation.reversal` marks it; `feeStatus` stays `waived` and a
  /// paid fee that went back to the wallet carries `refundedToWallet: true`
  /// and `refundedAt` (the amount is the `fee`). A `refunded` status from
  /// the first 0.18.8 draft is read the same. Anything else = no fee.
  static ({bool reversed, Money? refunded}) noShowReversal(
    Map<String, dynamic> ride,
  ) {
    final cancellation = ride['cancellation'];
    if (cancellation is! Map || cancellation['reversal'] is! Map) {
      return (reversed: false, refunded: null);
    }
    final refundedAt = cancellation['refundedAt'];
    final refunded =
        cancellation['refundedToWallet'] == true ||
        cancellation['feeStatus'] == 'refunded' ||
        (refundedAt is String && refundedAt.isNotEmpty);
    final fee = Money.fromWire(cancellation['fee']);
    return (
      reversed: true,
      refunded: refunded && fee != null && fee.isPositive ? fee : null,
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
