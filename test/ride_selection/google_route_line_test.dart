import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/quoted_route.dart';
import 'package:movera_rider/core/maps/routing_service.dart';
import 'package:movera_rider/features/ride_booking/application/trip_route_line.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';

/// v0.18.167 (contract.json#googleRouteLine, owner 2026-11-26 "Oui,
/// corriger"): the booking maps draw the Google route the quote was priced
/// on (`Quote.routePolyline`), with no route call and no "Approximate
/// route"; without it the straight line and the badge stay.
const _line = '_p~iF~ps|U_ulLnnqC_mqNvxq`@'; // Google's documented example
const _staging = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.example.test',
);
const _pickup = LatLng(59.3326, 18.0649);
const _dropoff = LatLng(59.3143, 18.0735);

Map<String, dynamic> _quote({String source = 'google', String? line}) => {
  'quoteId': 'qte_grl167',
  'categoryId': 'economy',
  'total': {'amountMinor': 21700, 'currency': 'SEK'},
  'fareLines': <Object>[],
  'expiresAt': '2099-01-01T00:00:00Z',
  'pickup': {'lat': _pickup.latitude, 'lng': _pickup.longitude},
  'dropoff': {'lat': _dropoff.latitude, 'lng': _dropoff.longitude},
  'stops': <Object>[],
  'tripSeconds': 1560,
  'routeSource': source,
  'routePolyline': ?line,
};

/// A routing seam that counts its calls and answers a straight line.
class _CountingRoutes extends RoutingService {
  int calls = 0;
  @override
  List<GeoPoint> line({required GeoPoint from, required GeoPoint to}) {
    calls++;
    return [from, to];
  }
}

void main() {
  setUp(QuotedRoutes.clear);

  test('decodes Google polylines; a broken line is null', () {
    final points = decodeGooglePolyline(_line)!;
    expect(points, hasLength(3));
    expect(points.first.latitude, closeTo(38.5, 1e-9));
    expect(points.first.longitude, closeTo(-120.2, 1e-9));
    expect(points.last.latitude, closeTo(43.252, 1e-9));
    expect(points.last.longitude, closeTo(-126.453, 1e-9));
    expect(decodeGooglePolyline('_p~iF~ps|U_ulL'), isNull);
    expect(decodeGooglePolyline(' '), isNull);
  });

  test('routePolyline is read only from a google quote', () {
    expect(
      ApiQuoteRepository.contractQuoteOf(_quote(line: _line))!.routePolyline,
      _line,
    );
    expect(
      ApiQuoteRepository.contractQuoteOf(
        _quote(source: 'estimate', line: _line),
      )!.routePolyline,
      isNull,
    );
    expect(ApiQuoteRepository.contractQuoteOf(_quote())!.routePolyline, isNull);
  });

  test('a google quote: the trip line is its route, not approximate, '
      'no route call', () async {
    final api = ApiClient(
      env: _staging,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/quotes');
        return http.Response(
          jsonEncode({
            'quotes': [_quote(line: _line)],
            'zoneId': 'Z001',
            'serverTime': '2026-11-26T08:00:00Z',
          }),
          201,
        );
      }),
    );
    final quote = await ApiQuoteRepository(api: api).quote(
      rideType: 'economy',
      distanceMeters: 3000,
      pickupPoint: GeoPoint(_pickup.latitude, _pickup.longitude),
      destinationPoint: GeoPoint(_dropoff.latitude, _dropoff.longitude),
    );
    expect(quote.routePolyline, _line);
    final routing = _CountingRoutes();
    final route = await roadTripLine(
      from: _pickup,
      stops: const [],
      to: _dropoff,
      routing: routing,
    );
    expect(route!.approximate, isFalse);
    expect(route.points, decodeGooglePolyline(_line));
    expect(routing.calls, 0);
  });

  test('no Google line (estimate): the straight line and the badge', () async {
    QuotedRoutes.remember([_pickup, _dropoff], 'broken_');
    final route = await roadTripLine(
      from: _pickup,
      stops: const [],
      to: _dropoff,
      routing: _CountingRoutes(),
    );
    expect(route!.approximate, isTrue);
    expect(route.points, [_pickup, _dropoff]);
  });

  test('another trip does not reuse the line', () {
    QuotedRoutes.remember([_pickup, _dropoff], _line);
    expect(QuotedRoutes.of([_dropoff, _pickup]), isNull);
    expect(QuotedRoutes.of([_pickup, _dropoff]), isNotNull);
  });

  test('follow-up: a re-quote priced as an estimate drops the older Google '
      'line of the same trip', () async {
    var source = 'google';
    final api = ApiClient(
      env: _staging,
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'quotes': [
              _quote(source: source, line: source == 'google' ? _line : null),
            ],
            'zoneId': 'Z001',
            'serverTime': '2026-11-26T08:00:00Z',
          }),
          201,
        ),
      ),
    );
    final repository = ApiQuoteRepository(api: api);
    Future<void> ask() => repository.quote(
      rideType: 'economy',
      distanceMeters: 3000,
      pickupPoint: GeoPoint(_pickup.latitude, _pickup.longitude),
      destinationPoint: GeoPoint(_dropoff.latitude, _dropoff.longitude),
    );
    await ask();
    expect(QuotedRoutes.of([_pickup, _dropoff]), isNotNull);
    source = 'estimate';
    repository.forgetAnswers();
    await ask();
    expect(QuotedRoutes.of([_pickup, _dropoff]), isNull);
  });

  test('v0.18.169 SHOULD 3: the tickets are trimmed with the kept lines', () {
    for (var i = 0; i < QuotedRoutes.limit * 3; i++) {
      final dropoff = LatLng(59.3 + i / 1000, 18.07);
      QuotedRoutes.remember(
        [_pickup, dropoff],
        _line,
        ticket: QuotedRoutes.nextTicket(),
      );
      QuotedRoutes.forget([
        dropoff,
        _pickup,
      ], ticket: QuotedRoutes.nextTicket());
    }
    expect(QuotedRoutes.ticketCount, lessThanOrEqualTo(QuotedRoutes.limit * 2));
  });
}
