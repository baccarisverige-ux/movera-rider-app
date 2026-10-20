import 'dart:convert';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/fare/domain/fare_rules.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

export 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart'
    show RideSnapshot;

/// A priced route change the rider has not confirmed yet.
class RouteChangeQuote {
  const RouteChangeQuote({
    required this.pickupAddress,
    required this.pickupPoint,
    required this.destinationAddress,
    required this.destinationPoint,
    required this.stops,
    required this.oldPriceKr,
    required this.newPriceKr,
    this.routeQuoteId,
    this.expiresAt,
    this.newTotalMinor,
    this.differenceMinor,
    this.expectedVersion,
    this.currency = Money.defaultCurrency,
  });

  final String pickupAddress;
  final GeoPoint pickupPoint;
  final String destinationAddress;
  final GeoPoint destinationPoint;
  final List<RouteStop> stops;
  /// Whole units of [currency] (the trip's, Q7).
  final double oldPriceKr;
  final double newPriceKr;

  /// ISO-4217 code of every amount of this change.
  final String currency;

  /// ARCH-14 / contract C-7: the server's id for this priced change, when it
  /// sends one. Apply sends it back with the amounts, so the server applies
  /// exactly the price the rider confirmed or refuses (409) and the rider
  /// sees the new price first.
  final String? routeQuoteId;
  final DateTime? expiresAt;
  final int? newTotalMinor;
  final int? differenceMinor;

  /// R-O2: the trip version the price was asked for. Applying sends it, so
  /// a change confirmed on a trip that moved on meanwhile is refused.
  final int? expectedVersion;

  /// Positive when the rider pays more, negative when money comes back.
  double get differenceKr => newPriceKr - oldPriceKr;

  Map<String, dynamic> toRequest() => {
    'pickupAddress': pickupAddress,
    'pickupLat': pickupPoint.latitude,
    'pickupLng': pickupPoint.longitude,
    'destinationAddress': destinationAddress,
    'destinationLat': destinationPoint.latitude,
    'destinationLng': destinationPoint.longitude,
    'stops': [for (final stop in stops) stop.toJson()],
  };
}

/// Why a route change could not be priced or applied.
enum RouteChangeFailure {
  pickupLocked,
  rideFinished,
  addressNotFound,
  network,
  priceChanged,

  /// R-O2: the trip changed since the rider's screen read it.
  stale,
}

class RouteChangeException implements Exception {
  const RouteChangeException(this.failure);
  final RouteChangeFailure failure;

  String get message => switch (failure) {
    RouteChangeFailure.pickupLocked =>
      'The driver is already at your pickup; only the destination and stops can change.',
    RouteChangeFailure.rideFinished => 'This ride can no longer be changed.',
    RouteChangeFailure.addressNotFound =>
      'Could not find that address. Try a more exact one.',
    RouteChangeFailure.network => 'Couldn’t update the route. Try again.',
    RouteChangeFailure.priceChanged =>
      'The price for this route changed. Check the new price and confirm again.',
    RouteChangeFailure.stale => rideJustChangedMessage,
  };
}

/// Changes the route of a ride that is being searched, waited for or driven:
/// prices the new route first, then applies it and tells the driver.
class RouteChangeController {
  RouteChangeController({
    required ApiClient api,
    required GeocodingRepository geocoding,
    RideSession? session,
  }) : _api = api,
       _geocoding = geocoding,
       _session = session;

  final ApiClient _api;
  final GeocodingRepository _geocoding;

  /// R-O2: where the trip's projection version comes from (and goes to).
  /// Without one, requests carry no `expectedVersion`.
  final RideSession? _session;

  /// The ride as last saved on this device, if any.
  static Future<RideSnapshot?> storedRide() => RideSnapshotStore.read();

  /// Prices the new route. Addresses without a point are geocoded first.
  Future<RouteChangeQuote> preview({
    required RideSnapshot ride,
    String? pickupAddress,
    GeoPoint? pickupPoint,
    required String destinationAddress,
    GeoPoint? destinationPoint,
    List<String> stops = const [],
    List<GeoPoint?> stopPoints = const [],
  }) async {
    final id = ride.rideId;
    if (id == null) throw const RouteChangeException(RouteChangeFailure.network);
    final pickup = pickupAddress?.trim().isNotEmpty == true
        ? pickupAddress!.trim()
        : ride.pickupAddress;
    final pickupAt = pickup == ride.pickupAddress
        ? GeoPoint(ride.pickupLat, ride.pickupLng)
        : pickupPoint ?? await _locate(pickup);
    final destination = destinationAddress.trim();
    final destinationAt = destination == ride.destinationAddress
        ? GeoPoint(ride.destinationLat, ride.destinationLng)
        : destinationPoint ?? await _locate(destination);
    final located = <RouteStop>[];
    for (var i = 0; i < stops.length; i++) {
      final address = stops[i].trim();
      if (address.isEmpty) continue;
      final known = ride.stops.where((s) => s.address == address).firstOrNull;
      final point =
          (i < stopPoints.length ? stopPoints[i] : null) ??
          (known == null ? null : GeoPoint(known.latitude, known.longitude)) ??
          await _locate(address);
      located.add(
        RouteStop(address: address, latitude: point.latitude, longitude: point.longitude),
      );
    }
    final draft = RouteChangeQuote(
      pickupAddress: pickup,
      pickupPoint: pickupAt,
      destinationAddress: destination,
      destinationPoint: destinationAt,
      stops: located,
      oldPriceKr: ride.price,
      newPriceKr: ride.price,
      currency: ride.currency,
    );
    final version = _session?.projectionVersionOf(id);
    final response = await _send(
      () => _api.post(
        '/api/v1/rides/$id/route-quote',
        body: {...draft.toRequest(), 'expectedVersion': ?version},
      ),
    );
    final price = _newPrice(response, ride.currency);
    final quoteId = response['routeQuoteId'];
    return RouteChangeQuote(
      pickupAddress: draft.pickupAddress,
      pickupPoint: draft.pickupPoint,
      destinationAddress: draft.destinationAddress,
      destinationPoint: draft.destinationPoint,
      stops: draft.stops,
      oldPriceKr: ride.price,
      newPriceKr: price?.major ?? ride.price,
      routeQuoteId:
          quoteId is String && quoteId.trim().isNotEmpty ? quoteId.trim() : null,
      expiresAt: WireTime.tryParse(response['expiresAt']),
      newTotalMinor: price?.amountMinor,
      differenceMinor:
          (Money.tryParse(response['difference']) ??
                  Money.tryMinor(
                    response['differenceMinor'],
                    response['currency'] ?? ride.currency,
                  ))
              ?.amountMinor,
      expectedVersion: version,
      currency: ride.currency,
    );
  }

  /// Applies a previewed change and returns the updated, saved snapshot.
  Future<RideSnapshot> apply({
    required RideSnapshot ride,
    required RouteChangeQuote quote,
    Object? refundTo,
  }) async {
    final id = ride.rideId;
    if (id == null) throw const RouteChangeException(RouteChangeFailure.network);
    final refund = refundTo?.toString().split('.').last;
    final body = <String, dynamic>{
      ...quote.toRequest(),
      'routeChange': true,
      // ARCH-14: the change and the price the rider confirmed, together.
      if (quote.routeQuoteId != null) 'routeQuoteId': quote.routeQuoteId,
      'expectedTotalMinor':
          quote.newTotalMinor ??
          Money.fromLegacyMajor(quote.newPriceKr, quote.currency).amountMinor,
      if (quote.differenceMinor != null)
        'expectedDifferenceMinor': quote.differenceMinor,
      // ARCH-9: the method by id. The label stays until the backend
      // contract is agreed.
      if (ride.paymentMethodId != null) 'paymentMethodId': ride.paymentMethodId,
      'paymentMethod': ride.paymentMethod,
      if (refund != null) 'refundTo': refund,
    };
    // ARCH-4: one key per confirmed change, the same on every send of it
    // (a retry after a timeout, a new controller, a reload), so the server
    // never charges or refunds the difference twice.
    final key = stableIdempotencyKey(
      'route-change',
      jsonEncode({'rideId': id, 'version': ride.version, ...body}),
    );
    // R-O2: the version the price was asked for, kept out of the key so a
    // resend of the same confirmed change is the same request.
    final expectedVersion = quote.expectedVersion;
    final response = await _send(
      () => _api.patch(
        '/api/v1/rides/$id',
        body: {...body, 'expectedVersion': ?expectedVersion},
        idempotencyKey: key,
      ),
    );
    _session?.observeProjection(response);
    final newPrice =
        _newPrice(response, ride.currency)?.major ?? quote.newPriceKr;
    final serverRide = response['ride'];
    final serverMax = serverRide is Map ? serverRide['maxOfferMinor'] : null;
    final updated = ride.copyWith(
      savedAt: DateTime.now(),
      pickupAddress: quote.pickupAddress,
      pickupLat: quote.pickupPoint.latitude,
      pickupLng: quote.pickupPoint.longitude,
      destinationAddress: quote.destinationAddress,
      destinationLat: quote.destinationPoint.latitude,
      destinationLng: quote.destinationPoint.longitude,
      stops: quote.stops,
      price: newPrice,
      // ARCH-20: a new route has a new offer ceiling.
      maxOfferMinor: serverMax is num && serverMax > 0
          ? serverMax.round()
          : ride.maxOfferMinor == null
          ? null
          : Money.fromLegacyMajor(FareRules.maximum(newPrice), ride.currency)
                .amountMinor,
    );
    await RideSnapshotStore.save(updated);
    return updated;
  }

  /// ARCH-11: the new total in minor units wins; the legacy whole-unit
  /// field is read only when the server sends nothing else. A total in
  /// another currency than the trip's ([currency]) is not its price.
  static Money? _newPrice(Map<String, dynamic> response, String currency) {
    final price =
        Money.tryParse(response['newTotal']) ??
        Money.tryMinor(
          response['newTotalMinor'],
          response['currency'] ?? currency,
        ) ??
        Money.tryLegacyMajor(response['newPriceKr'], currency);
    return price != null && price.currency == currency ? price : null;
  }

  Future<GeoPoint> _locate(String address) async {
    final PlaceResult? found;
    try {
      found = await _geocoding.forward(address);
    } catch (_) {
      throw const RouteChangeException(RouteChangeFailure.network);
    }
    if (found == null) {
      throw const RouteChangeException(RouteChangeFailure.addressNotFound);
    }
    return found.point;
  }

  Future<Map<String, dynamic>> _send(
    Future<Map<String, dynamic>> Function() call,
  ) async {
    try {
      return await call();
    } on ApiError catch (error) {
      _session?.observeProjection(error.projection);
      if (error.isVersionMismatch) {
        throw const RouteChangeException(RouteChangeFailure.stale);
      }
      // R-O4: the lower-case reason beside the contract code, else the
      // contract code itself.
      throw RouteChangeException(switch (error.detail) {
        'pickup_locked' => RouteChangeFailure.pickupLocked,
        'ride_finished' || 'invalid_transition' => RouteChangeFailure.rideFinished,
        'route_quote_expired' ||
        'route_quote_not_found' ||
        'route_quote_mismatch' ||
        'route_quote_price_changed' ||
        'conflict' => RouteChangeFailure.priceChanged,
        _ => RouteChangeFailure.network,
      });
    } catch (_) {
      throw const RouteChangeException(RouteChangeFailure.network);
    }
  }
}
