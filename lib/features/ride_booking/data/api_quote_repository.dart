import 'dart:convert';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/contracts/category_ids.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';

class ApiQuoteRepository implements QuoteRepository {
  ApiQuoteRepository({required this.api, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ApiClient api;
  final DateTime Function() _clock;
  bool lastUsedFallback = false;

  /// How long one `POST /quotes` answer (a quote per category of the zone)
  /// serves the other categories of the same route. Select Ride asks per
  /// category in small batches; within this window they share one request.
  static const batchReuse = Duration(seconds: 20);

  final Map<String, _QuoteBatch> _batches = {};

  /// The places each contract quote was priced for, by quoteId. A contract
  /// trip must name exactly the quoted pickup, dropoff and stops (server
  /// `quote_mismatch` otherwise), so booking sends these.
  static final Map<String, QuotedRoute> _routes = {};

  /// Contract quotes already booked: the server takes a quote once
  /// (`quote_used`), so a batch holding one is not reused.
  static final Set<String> _booked = {};

  /// The route [quoteId] was priced for, when this app asked for it.
  static QuotedRoute? routeOf(String? quoteId) =>
      quoteId == null ? null : _routes[quoteId];

  /// [quoteId] went into a trip; it is never offered again.
  static void markBooked(String quoteId) {
    _booked.add(quoteId);
    _routes.remove(quoteId);
  }

  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) async {
    lastUsedFallback = false;
    if (api.contractWire) {
      return _contractQuote(
        rideType: rideType,
        pickup: pickup,
        destination: destination,
        pickupPoint: pickupPoint,
        destinationPoint: destinationPoint,
        stops: stops,
      );
    }
    try {
      final json = await api.post(
        '/api/v1/quotes',
        body: {
          'rideType': rideType,
          'distanceMeters': distanceMeters,
          'durationSeconds': durationSeconds,
          'pickup': pickup,
          'destination': destination,
          // ARCH-8 / contract C-2: the points the server routes and prices.
          // The fields above stay until the backend contract is agreed.
          if (pickupPoint != null) ...{
            'pickupLat': pickupPoint.latitude,
            'pickupLng': pickupPoint.longitude,
          },
          if (destinationPoint != null) ...{
            'destinationLat': destinationPoint.latitude,
            'destinationLng': destinationPoint.longitude,
          },
          if (stops.isNotEmpty)
            'stops': [for (final stop in stops) stop.toJson()],
          'apiVersion': 'v1',
        },
      );
      final raw = json['quote'];
      if (raw is! Map) {
        throw const FormatException('malformed quote');
      }
      final map = Map<String, dynamic>.from(raw);
      // ARCH-11 / contract C-0: integer minor units and an ISO-4217 code,
      // either as a `total` Money object or as `totalMinor` + `currency`.
      final total =
          Money.fromWire(map['total']) ??
          Money.tryMinor(
            map['totalMinor'] ?? map['amountMinor'],
            map['currency'] ?? Money.defaultCurrency,
          );
      if (total == null) throw const FormatException('malformed quote');
      final rawId = map['quoteId'] ?? map['id'];
      if (rawId is! String || rawId.trim().isEmpty) {
        throw const FormatException('quote id missing');
      }
      final signedPayload = map['signedPayload'];
      if (signedPayload is! String || signedPayload.trim().isEmpty) {
        throw const FormatException('quote signature missing');
      }
      final expires = WireTime.tryParse(map['expiresAt']);
      if (expires == null) throw const FormatException('quote expiry missing');
      final quote = RideQuote(
        id: rawId.trim(),
        rideType: (map['rideType'] ?? rideType).toString(),
        totalMinor: total.amountMinor,
        currency: total.currency,
        expiresAt: expires,
        baseMinor:
            (map['breakdown'] is Map
                    ? (map['breakdown']['baseMinor'] as num?)
                    : null)
                ?.round() ??
            total.amountMinor,
        distanceMinor:
            (map['breakdown'] is Map
                    ? (map['breakdown']['distanceMinor'] as num?)
                    : null)
                ?.round() ??
            0,
        timeMinor:
            (map['breakdown'] is Map
                    ? (map['breakdown']['timeMinor'] as num?)
                    : null)
                ?.round() ??
            0,
        bookingFeeMinor:
            (map['breakdown'] is Map
                    ? (map['breakdown']['bookingFeeMinor'] as num?)
                    : null)
                ?.round() ??
            0,
        discountMinor:
            (map['breakdown'] is Map
                    ? (map['breakdown']['discountMinor'] as num?)
                    : null)
                ?.round() ??
            0,
        signedPayload: signedPayload.trim(),
      );
      if (quote.expired) throw StateError('expired quote');
      return quote;
    } catch (error, stack) {
      lastUsedFallback = false;
      AppLog.error(
        'quote.unavailable',
        extra: {'rideType': rideType, 'reason': error.toString()},
      );
      AppLog.error(
        'quote.unavailable.stack',
        extra: {'stack': stack.toString()},
      );
      rethrow;
    }
  }

  /// Contract `POST /quotes` (openapi `QuoteRequest` → `QuoteList`): the
  /// route as Places, every category of the pickup's zone in one answer.
  /// A category the zone does not offer has no quote: it is unavailable.
  Future<RideQuote> _contractQuote({
    required String rideType,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) async {
    try {
      if (pickupPoint == null || destinationPoint == null) {
        throw const FormatException('a quote needs the pickup and dropoff');
      }
      final body = <String, dynamic>{
        'pickup': contractPlace(
          pickupPoint.latitude,
          pickupPoint.longitude,
          pickup,
        ),
        'dropoff': contractPlace(
          destinationPoint.latitude,
          destinationPoint.longitude,
          destination,
        ),
        'stops': [
          for (final stop in stops)
            contractPlace(stop.latitude, stop.longitude, stop.address),
        ],
      };
      final key = jsonEncode(body);
      final category = CategoryIds.canonical(rideType);
      for (var attempt = 0; attempt < 2; attempt++) {
        final batch = _batchFor(key, body);
        final Map<String, RideQuote> quotes;
        try {
          quotes = await batch.quotes;
        } catch (_) {
          if (identical(_batches[key], batch)) _batches.remove(key);
          rethrow;
        }
        final found = quotes[category];
        if (found == null) throw QuoteCategoryNotOffered(category);
        if (_booked.contains(found.id) || found.expired) {
          // Spent or stale: ask the server once more for this route.
          if (identical(_batches[key], batch)) _batches.remove(key);
          continue;
        }
        return RideQuote(
          id: found.id,
          rideType: rideType,
          totalMinor: found.totalMinor,
          currency: found.currency,
          expiresAt: found.expiresAt,
          baseMinor: found.baseMinor,
          distanceMinor: found.distanceMinor,
          timeMinor: found.timeMinor,
          bookingFeeMinor: found.bookingFeeMinor,
          surgeMinor: found.surgeMinor,
          discountMinor: found.discountMinor,
          serverHeld: true,
        );
      }
      throw StateError('no fresh quote for $category');
    } catch (error, stack) {
      AppLog.error(
        'quote.unavailable',
        extra: {'rideType': rideType, 'reason': error.toString()},
      );
      AppLog.error(
        'quote.unavailable.stack',
        extra: {'stack': stack.toString()},
      );
      rethrow;
    }
  }

  _QuoteBatch _batchFor(String key, Map<String, dynamic> body) {
    final now = _clock();
    _batches.removeWhere((_, batch) => now.difference(batch.at) > batchReuse);
    return _batches[key] ??= _QuoteBatch(now, _fetchBatch(body));
  }

  Future<Map<String, RideQuote>> _fetchBatch(Map<String, dynamic> body) async {
    final json = await api.post(
      '/api/v1/quotes',
      body: body,
      // contract.json#headers: every mutation names its own key.
      idempotencyKey: newIdempotencyKey('quote'),
    );
    final raw = json['quotes'];
    if (raw is! List) throw const FormatException('malformed quote list');
    final quotes = <String, RideQuote>{};
    // Routes of quotes that ran out are of no use to a booking any more.
    final now = DateTime.now();
    _routes.removeWhere((_, route) => route.expiresAt.isBefore(now));
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final quote = contractQuoteOf(map);
      if (quote == null) continue;
      quotes[quote.rideType] = quote;
      _routes[quote.id] = QuotedRoute(
        expiresAt: quote.expiresAt.add(const Duration(minutes: 1)),
        pickup:
            _placeOf(map['pickup']) ?? body['pickup'] as Map<String, dynamic>,
        dropoff:
            _placeOf(map['dropoff']) ?? body['dropoff'] as Map<String, dynamic>,
        stops: map['stops'] is List
            ? [
                for (final stop in map['stops'] as List)
                  if (_placeOf(stop) case final place?) place,
              ]
            : List<Map<String, dynamic>>.from(body['stops'] as List),
      );
    }
    return quotes;
  }

  /// A contract `Quote` as a [RideQuote] keyed by its canonical category,
  /// or null when a required field is missing or malformed.
  static RideQuote? contractQuoteOf(Map<String, dynamic> map) {
    final id = map['quoteId'];
    final category = CategoryIds.tryCanonical(map['categoryId']);
    final total = Money.fromWire(map['total']);
    final expires = WireTime.tryParse(map['expiresAt']);
    if (id is! String ||
        id.trim().isEmpty ||
        category == null ||
        total == null ||
        expires == null) {
      return null;
    }
    int line(Set<String> codes) {
      var sum = 0;
      final lines = map['fareLines'];
      if (lines is! List) return 0;
      for (final item in lines) {
        if (item is! Map || !codes.contains(item['code'])) continue;
        final amount = Money.fromWire(item['amount']);
        if (amount != null && amount.currency == total.currency) {
          sum += amount.amountMinor;
        }
      }
      return sum;
    }

    return RideQuote(
      id: id.trim(),
      rideType: category,
      totalMinor: total.amountMinor,
      currency: total.currency,
      expiresAt: expires,
      baseMinor: line(const {'base', 'fixed_route'}),
      distanceMinor: line(const {'distance'}),
      timeMinor: line(const {'time'}),
      bookingFeeMinor: line(const {'app_fee', 'pickup_fee', 'reservation_fee'}),
      surgeMinor: line(const {'surge'}),
      // A discount line is negative on the wire; the app keeps it positive.
      discountMinor: -line(const {'discount'}),
      serverHeld: true,
    );
  }

  /// A contract `Place`: `{address?, lat, lng}` (address at most 512).
  static Map<String, dynamic> contractPlace(
    double lat,
    double lng, [
    String? address,
  ]) {
    final label = address?.trim();
    return {
      if (label != null && label.isNotEmpty)
        'address': label.length > 512 ? label.substring(0, 512) : label,
      'lat': lat,
      'lng': lng,
    };
  }

  static Map<String, dynamic>? _placeOf(Object? raw) {
    if (raw is! Map || raw['lat'] is! num || raw['lng'] is! num) return null;
    return Map<String, dynamic>.from(raw);
  }
}

/// The server priced the route and gave no quote for [categoryId]: the
/// pickup's zone does not offer it (contract `POST /quotes` without
/// `categoryIds` answers every category the zone has).
class QuoteCategoryNotOffered implements Exception {
  const QuoteCategoryNotOffered(this.categoryId);

  final String categoryId;

  @override
  String toString() => 'QuoteCategoryNotOffered($categoryId)';
}

/// The route a contract quote was priced for, as the server echoed it.
class QuotedRoute {
  const QuotedRoute({
    required this.pickup,
    required this.dropoff,
    this.stops = const [],
    required this.expiresAt,
  });

  /// After this the quote can no longer be booked.
  final DateTime expiresAt;

  final Map<String, dynamic> pickup;
  final Map<String, dynamic> dropoff;
  final List<Map<String, dynamic>> stops;
}

class _QuoteBatch {
  _QuoteBatch(this.at, this.quotes) {
    // An unawaited failure is handled by the caller that awaits it.
    quotes.ignore();
  }

  final DateTime at;
  final Future<Map<String, RideQuote>> quotes;
}
