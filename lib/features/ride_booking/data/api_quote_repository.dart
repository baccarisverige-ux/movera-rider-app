import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';

class ApiQuoteRepository implements QuoteRepository {
  ApiQuoteRepository({required this.api});

  final ApiClient api;
  bool lastUsedFallback = false;

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
        extra: {
          'rideType': rideType,
          'reason': error.toString(),
        },
      );
      AppLog.error('quote.unavailable.stack', extra: {'stack': stack.toString()});
      rethrow;
    }
  }
}
