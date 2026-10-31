import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/trip_eta.dart';

/// Driver group 5, status item 2 + Q4 (contract v0.18.7
/// `pickupWaiting.eta`): the rider shows the server's road-route ETA as
/// whole minutes (rounded up, at least 1) and the distance as the owner
/// said: km with one decimal from 1 km, 100 m steps under 1 km, 10 m steps
/// under 100 m, rounded down, never under 10 m. The fixture cases are the
/// same the server and the driver app answer.
void main() {
  group('distance display (fixtures/pickup_waiting.json#distanceDisplay)', () {
    late List<dynamic> cases;

    setUpAll(() async {
      final text = await File(
        'contracts/fixtures/pickup_waiting.json',
      ).readAsString();
      cases =
          (jsonDecode(text) as Map<String, dynamic>)['distanceDisplay']
              as List<dynamic>;
    });

    test('every fixture case gives the same unit and value', () {
      expect(cases, isNotEmpty);
      for (final raw in cases) {
        final c = raw as Map<String, dynamic>;
        final shown = EtaDistance.of(c['meters'] as int);
        expect(shown.unit, c['unit'], reason: 'meters=${c['meters']}');
        expect(shown.value, c['value'], reason: 'meters=${c['meters']}');
      }
    });
  });

  test('the number is written in the app language (sv 3,4 km, en 3.4 km)', () {
    expect(EtaDistance.of(3449).format('sv'), '3,4 km');
    expect(EtaDistance.of(3449).format('fr'), '3,4 km');
    expect(EtaDistance.of(3449).format('en'), '3.4 km');
    expect(EtaDistance.of(1000).format('sv'), '1,0 km');
    expect(EtaDistance.of(850).format('sv'), '800 m');
    expect(EtaDistance.of(85).format('fr'), '80 m');
    expect(EtaDistance.of(0).format('en'), '10 m');
  });

  test('ETA minutes are rounded up and never under 1', () {
    expect(TripEta.minutesOf(60), 1);
    expect(TripEta.minutesOf(61), 2);
    expect(TripEta.minutesOf(119), 2);
    expect(TripEta.minutesOf(120), 2);
    expect(TripEta.minutesOf(0), 1);
    expect(TripEta.minutesOf(15), 1);
  });

  test('TripEta reads the wire shape and refuses a half one', () {
    final eta = TripEta.fromWire({
      'etaSeconds': 250,
      'distanceMeters': 1234,
      'target': 'pickup',
      'at': '2026-10-31T10:00:00.000Z',
      'source': 'osrm',
    });
    expect(eta, isNotNull);
    expect(eta!.minutes, 5);
    expect(eta.toPickup, isTrue);
    expect(eta.source, 'osrm');
    expect(eta.at, DateTime.utc(2026, 10, 31, 10));
    expect(TripEta.fromWire({'etaSeconds': 250}), isNull);
    expect(TripEta.fromWire('nope'), isNull);
    // `source` is optional for an older server: the estimate then.
    expect(
      TripEta.fromWire({
        'etaSeconds': 90,
        'distanceMeters': 300,
        'target': 'dropoff',
        'at': '2026-10-31T10:00:00.000Z',
      })?.source,
      'estimate',
    );
  });
}
