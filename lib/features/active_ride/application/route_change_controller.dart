import 'dart:convert';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/on_trip.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_distance.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/fare/domain/fare_rules.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/l10n/l10n.dart';

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
  ///
  /// rider-u36: the server's `differenceMinor` (what it charges or refunds,
  /// against the trip's fare as the server holds it) wins; the difference
  /// to this device's price is only a fallback for a server that sends none.
  double get differenceKr => differenceMinor != null
      ? Money(differenceMinor!, currency).major
      : newPriceKr - oldPriceKr;

  /// rider-u43: true when the change costs or refunds anything, compared in
  /// minor units. A "below half a unit" rule hid real cent and millime
  /// changes (18.20 € to 18.60 €) as "Same price" in EUR and TND zones.
  bool get changesPrice =>
      (differenceMinor ??
          Money.fromLegacyMajor(differenceKr, currency).amountMinor) !=
      0;

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

  /// Q40: after accept the pickup may move only a short way.
  pickupTooFar,

  /// P5-R4: the server does not offer route changes.
  unavailable,

  /// v0.18.9 (G7 decision 5): more stops than the zone's `booking.maxStops`.
  tooManyStops,

  /// v0.18.9: a change already waits for the driver.
  pending,
}

class RouteChangeException implements Exception {
  const RouteChangeException(
    this.failure, {
    this.maxPickupMoveMeters,
    this.maxStops,
  });
  final RouteChangeFailure failure;

  /// The zone's limit behind [RouteChangeFailure.tooManyStops].
  final int? maxStops;

  /// The zone's limit behind [RouteChangeFailure.pickupTooFar] (Q40).
  final int? maxPickupMoveMeters;

  String get message => switch (failure) {
    RouteChangeFailure.pickupLocked => L10n.current.routePickupLocked,
    RouteChangeFailure.rideFinished => L10n.current.routeNoLongerChangeable,
    RouteChangeFailure.addressNotFound => L10n.current.routeAddressNotFound,
    RouteChangeFailure.network => L10n.current.routeUpdateFailed,
    RouteChangeFailure.priceChanged => L10n.current.routePriceChanged,
    RouteChangeFailure.stale => rideJustChangedMessage,
    RouteChangeFailure.unavailable => L10n.current.routeChangeUnavailable,
    RouteChangeFailure.tooManyStops => L10n.current.g7TooManyStops(
      '${maxStops ?? RiderAppConfig.defaultMaxStops}',
    ),
    RouteChangeFailure.pending => L10n.current.g7RouteWaiting,
    RouteChangeFailure.pickupTooFar => L10n.current.routePickupTooFar(
      '${maxPickupMoveMeters ?? RiderAppConfig.defaultMaxPickupMoveAfterAcceptMeters}',
    ),
  };
}

/// Changes the route of a ride that is being searched, waited for or driven:
/// prices the new route first, then applies it and tells the driver.
class RouteChangeController {
  RouteChangeController({
    required ApiClient api,
    required GeocodingRepository geocoding,
    RideSession? session,
    bool zoneAllows = false,
    int? maxStops,
  }) : _api = api,
       _geocoding = geocoding,
       _session = session,
       _zoneAllows = zoneAllows,
       _maxStops = maxStops;

  /// Contract v0.18.9 (G7 decision 3): the trip zone's `routeChange.on`.
  /// On the contract wire a change is offered only when it is on.
  final bool _zoneAllows;

  /// The zone's `booking.maxStops` (G7 decision 5); null = not checked here
  /// (the server still refuses `too_many_stops`).
  final int? _maxStops;

  final ApiClient _api;
  final GeocodingRepository _geocoding;

  /// R-O2: where the trip's projection version comes from (and goes to).
  /// Without one, requests carry no `expectedVersion`.
  final RideSession? _session;

  /// Audit Phase 5 (P5-R4): whether this server changes a booked route.
  /// movera-server answers `POST /trips/{id}/route-quote` and
  /// `PATCH /trips/{id}` with 404 `operation_not_enabled`, and this
  /// controller still speaks the demo's `/rides/{id}` dialect, so on the
  /// contract wire a change could never be priced: the rider is told so
  /// before editing anything, and no request is sent.
  ///
  /// Contract v0.18.9 (driver group 7): movera-server prices and applies a
  /// change (`/trips/{id}/route-quote`, `PATCH /trips/{id}`), so on the
  /// contract wire it is offered when the trip zone switches it on.
  bool get available => !_api.contractWire || _zoneAllows;

  /// True when this controller speaks the contract (v0.18.9) wire.
  bool get contractWire => _api.contractWire;

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
    int? maxPickupMoveMeters,
  }) async {
    if (!available) {
      throw const RouteChangeException(RouteChangeFailure.unavailable);
    }
    final id = ride.rideId;
    if (id == null) {
      throw const RouteChangeException(RouteChangeFailure.network);
    }
    final pickup = pickupAddress?.trim().isNotEmpty == true
        ? pickupAddress!.trim()
        : ride.pickupAddress;
    // rider-u37: a point the rider placed (map pick, suggestion) wins, even
    // when its label is the current address; only a bare label is looked up.
    final pickupAt =
        pickupPoint ??
        (pickup == ride.pickupAddress
            ? GeoPoint(ride.pickupLat, ride.pickupLng)
            : await _locate(pickup));
    // Q40: once a driver has accepted, a pickup further than the limit is a
    // new ride, not a route change.
    if (maxPickupMoveMeters != null &&
        GeoDistance.metersBetween(
              ride.pickupLat,
              ride.pickupLng,
              pickupAt.latitude,
              pickupAt.longitude,
            ) >
            maxPickupMoveMeters) {
      throw RouteChangeException(
        RouteChangeFailure.pickupTooFar,
        maxPickupMoveMeters: maxPickupMoveMeters,
      );
    }
    final destination = destinationAddress.trim();
    final destinationAt =
        destinationPoint ??
        (destination == ride.destinationAddress
            ? GeoPoint(ride.destinationLat, ride.destinationLng)
            : await _locate(destination));
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
        RouteStop(
          address: address,
          latitude: point.latitude,
          longitude: point.longitude,
        ),
      );
    }
    final max = _maxStops;
    if (max != null && located.length > max) {
      throw RouteChangeException(
        RouteChangeFailure.tooManyStops,
        maxStops: max,
      );
    }
    if (_api.contractWire) {
      return _contractQuote(
        ride: ride,
        id: id,
        destination: destination,
        destinationAt: destinationAt,
        stops: located,
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
      routeQuoteId: quoteId is String && quoteId.trim().isNotEmpty
          ? quoteId.trim()
          : null,
      expiresAt: WireTime.tryParse(response['expiresAt']),
      newTotalMinor: price?.amountMinor,
      differenceMinor:
          (Money.fromWire(response['difference']) ??
                  Money.tryMinor(
                    response['differenceMinor'],
                    response['currency'] ?? ride.currency,
                  ))
              ?.amountMinor,
      expectedVersion: version,
      currency: ride.currency,
    );
  }

  /// v0.18.9 `POST /trips/{id}/route-quote { expectedVersion, dropoff,
  /// stops }` → `RouteQuote { routeQuoteId, total, difference, expiresAt }`.
  /// The pickup stays (the server prices from where the trip is).
  Future<RouteChangeQuote> _contractQuote({
    required RideSnapshot ride,
    required String id,
    required String destination,
    required GeoPoint destinationAt,
    required List<RouteStop> stops,
  }) async {
    final version = _session?.projectionVersionOf(id);
    final response = await _send(
      () => _api.post(
        '/api/v1/trips/${Uri.encodeComponent(id)}/route-quote',
        body: {
          'expectedVersion': ?version,
          'dropoff': {
            'lat': destinationAt.latitude,
            'lng': destinationAt.longitude,
            'address': destination,
          },
          'stops': [
            for (final stop in stops)
              {
                'lat': stop.latitude,
                'lng': stop.longitude,
                'address': stop.address,
              },
          ],
        },
      ),
    );
    final total = Money.fromWire(response['total']);
    final price = total != null && total.currency == ride.currency
        ? total
        : null;
    final quoteId = response['routeQuoteId'];
    return RouteChangeQuote(
      pickupAddress: ride.pickupAddress,
      pickupPoint: GeoPoint(ride.pickupLat, ride.pickupLng),
      destinationAddress: destination,
      destinationPoint: destinationAt,
      stops: stops,
      oldPriceKr: ride.price,
      newPriceKr: price?.major ?? ride.price,
      routeQuoteId: quoteId is String && quoteId.trim().isNotEmpty
          ? quoteId.trim()
          : null,
      expiresAt: WireTime.tryParse(response['expiresAt']),
      newTotalMinor: price?.amountMinor,
      differenceMinor: Money.fromWire(response['difference'])?.amountMinor,
      expectedVersion: version,
      currency: ride.currency,
    );
  }

  /// v0.18.9 `PATCH /trips/{id} { expectedVersion, routeQuoteId }`: the
  /// driver is asked; the route changes only once they accept (or at once
  /// when the zone lets no driver refuse). Returns the projection's
  /// `routeChange` (pending, or accepted by the system).
  Future<TripRouteChange?> propose({
    required RideSnapshot ride,
    required RouteChangeQuote quote,
  }) async {
    final id = ride.rideId;
    final quoteId = quote.routeQuoteId;
    if (id == null || quoteId == null) {
      throw const RouteChangeException(RouteChangeFailure.network);
    }
    final version = _session?.projectionVersionOf(id) ?? quote.expectedVersion;
    final response = await _send(
      () => _api.patch(
        '/api/v1/trips/${Uri.encodeComponent(id)}',
        body: {'expectedVersion': ?version, 'routeQuoteId': quoteId},
        idempotencyKey: stableIdempotencyKey('route-change', quoteId),
      ),
    );
    _session?.observeProjection(response);
    return TripRouteChange.fromWire(response['routeChange']);
  }

  /// v0.18.9 `POST /trips/{id}/route-change/withdraw { expectedVersion,
  /// changeId }`: the rider takes a pending change back.
  Future<TripRouteChange?> withdraw({
    required String tripId,
    required String changeId,
  }) async {
    final version = _session?.projectionVersionOf(tripId);
    final response = await _send(
      () => _api.post(
        '/api/v1/trips/${Uri.encodeComponent(tripId)}/route-change/withdraw',
        body: {'expectedVersion': ?version, 'changeId': changeId},
      ),
    );
    _session?.observeProjection(response);
    return TripRouteChange.fromWire(response['routeChange']);
  }

  /// The saved ride once the driver accepted [change]: its drop-off, stops
  /// and new total.
  static Future<RideSnapshot> adoptAccepted(
    RideSnapshot ride,
    TripRouteChange change,
  ) async {
    final drop = change.dropoff;
    final total = change.total;
    final updated = ride.copyWith(
      savedAt: DateTime.now(),
      destinationAddress: drop?.address ?? ride.destinationAddress,
      destinationLat: drop?.lat ?? ride.destinationLat,
      destinationLng: drop?.lng ?? ride.destinationLng,
      stops: [
        for (final stop in change.stops)
          RouteStop(
            address: stop.address ?? '',
            latitude: stop.lat,
            longitude: stop.lng,
          ),
      ],
      price: total != null && total.currency == ride.currency
          ? total.major
          : ride.price,
    );
    await RideSnapshotStore.save(updated);
    return updated;
  }

  /// Applies a previewed change and returns the updated, saved snapshot.
  Future<RideSnapshot> apply({
    required RideSnapshot ride,
    required RouteChangeQuote quote,
    Object? refundTo,
  }) async {
    final id = ride.rideId;
    if (id == null) {
      throw const RouteChangeException(RouteChangeFailure.network);
    }
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
    Future<Map<String, dynamic>> patch() => _api.patch(
      '/api/v1/rides/$id',
      body: {...body, 'expectedVersion': ?expectedVersion},
      idempotencyKey: key,
    );
    final response = await _send(() async {
      try {
        return await patch();
      } catch (error) {
        // rider-u38: a timeout or dropped connection says nothing about
        // whether the server applied the change. The same request again
        // (same key) gets the server's answer, so a change it already
        // applied is adopted instead of being reported as failed.
        if (error is ApiError && !error.isRetryable) rethrow;
        return await patch();
      }
    });
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
          : Money.fromLegacyMajor(
              FareRules.maximum(newPrice),
              ride.currency,
            ).amountMinor,
    );
    await RideSnapshotStore.save(updated);
    return updated;
  }

  /// ARCH-11: the new total in minor units wins; the legacy whole-unit
  /// field is read only when the server sends nothing else. A total in
  /// another currency than the trip's ([currency]) is not its price.
  static Money? _newPrice(Map<String, dynamic> response, String currency) {
    final price =
        Money.fromWire(response['newTotal']) ??
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
      if (error.detail == 'too_many_stops') {
        final max = (error.details ?? const <String>[])
            .map((d) => RegExp(r'^maxStops=(\d+)$').firstMatch(d))
            .whereType<RegExpMatch>()
            .map((m) => int.parse(m.group(1)!))
            .firstOrNull;
        throw RouteChangeException(
          RouteChangeFailure.tooManyStops,
          maxStops: max ?? _maxStops,
        );
      }
      throw RouteChangeException(switch (error.detail) {
        'pickup_locked' => RouteChangeFailure.pickupLocked,
        'pickup_too_far' => RouteChangeFailure.pickupTooFar,
        'ride_finished' ||
        'invalid_transition' => RouteChangeFailure.rideFinished,
        'route_change_pending' => RouteChangeFailure.pending,
        'route_change_off' ||
        'route_change_fixed_route' => RouteChangeFailure.unavailable,
        'visited_stop_changed' ||
        'route_change_not_pending' => RouteChangeFailure.rideFinished,
        'route_quote_used' ||
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
