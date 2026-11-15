import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/rider_in_trip_panel.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../contracts/contract_fixtures.dart';

/// Job C9b (contract v0.18.108 §93, `contract.json#autoArrive.stops`; owner
/// 2026-11-02 "At the pickup AND at stops", Rules
/// decisions/driver-g7.md:84): while the server marks the open middle stop
/// as away (`stops[i].away`, the driver drove more than leaveMeters from
/// it) the stop wait stands still, and the rider's in-trip panel says so
/// (`autoArrive.stops.texts.riderStopPaused`); gone when back. The rider
/// gets no amounts and the phone works out no money.
///
/// The texts are the v0.18.108 contract's (movera-contracts 0acefe8,
/// contract.json `autoArrive.stops.texts.riderStopPaused`); the test also
/// checks them against the synced contract copy (as data, never a source
/// read).
const _riderStopPaused = {
  'sv': 'Väntetiden är pausad: din förare är inte vid stoppet.',
  'fr': 'Temps d’attente en pause : votre chauffeur n’est plus à l’arrêt.',
  'en': 'Waiting time paused: your driver is away from the stop.',
};

void _noop() {}

Widget _panel({bool stopPaused = false, String? stopNote}) => MaterialApp(
  home: Scaffold(
    body: RiderInTripPanel(
      destinationAddress: 'Hornsgatan 2, Stockholm',
      rideType: 'Movera',
      paymentMethod: 'Apple Pay',
      price: 259,
      driver: null,
      rideId: 'c9b-trip',
      onOpenProfile: _noop,
      onCall: _noop,
      onMore: _noop,
      onCancel: _noop,
      stopNote: stopNote,
      stopPaused: stopPaused,
    ),
  ),
);

class _Feed implements RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast();
  int _sequence = 0;

  void add(RideStatus status, {Map<String, Object?> payload = const {}}) {
    _sequence += 1;
    _events.add(
      RideRealtimeEvent(
        tripId: 'c9b-trip',
        status: status,
        sequence: _sequence,
        version: _sequence,
        kind: RealtimeKind.tripProjection,
        driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
        payload: {wholeProjectionKey: true, ...payload},
      ),
    );
  }

  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => _events.stream;
  @override
  Future<void> reconnectAndResync(String rideId) async {}
  @override
  Future<void> sendSignal({
    required String rideId,
    required RideRealtimeSignal signal,
    String? message,
  }) async {}
  @override
  void unsubscribe() {}
  @override
  void cancelRide() {}
  @override
  void researchAfterDriverCancel() {}
  @override
  void dispose() => unawaited(_events.close());
}

Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('texts.riderStopPaused is the contract text in sv, fr and en', () {
    // The contract copy as data (test/contracts/contract_fixtures.dart reads
    // bytes), never a source read (CI Phase 69: fewer than 40 grep tests).
    final texts =
        ((contract['autoArrive'] as Map)['stops'] as Map)['texts']['riderStopPaused']
            as Map;
    for (final lang in ['sv', 'fr', 'en']) {
      expect(texts[lang], _riderStopPaused[lang], reason: 'copy $lang');
      expect(
        lookupAppLocalizations(Locale(lang)).stopWaitingPausedDriverAway,
        _riderStopPaused[lang],
        reason: lang,
      );
    }
  });

  testWidgets('in-trip panel: the paused line while the stop is away, '
      'next to the stop price; no line when not away', (tester) async {
    await tester.pumpWidget(
      _panel(stopPaused: true, stopNote: 'Waiting at a stop: 4,50 kr/min'),
    );
    expect(find.text(_riderStopPaused['en']!), findsOneWidget);
    expect(find.byKey(const ValueKey('in-trip-stop-paused')), findsOneWidget);
    expect(find.text('Waiting at a stop: 4,50 kr/min'), findsOneWidget);

    await tester.pumpWidget(_panel(stopNote: 'Waiting at a stop: 4,50 kr/min'));
    expect(find.text(_riderStopPaused['en']!), findsNothing);
    expect(find.byKey(const ValueKey('in-trip-stop-paused')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('projection stops[i].away reaches the app', () {
    Future<RideRealtimeEvent> eventFor(
      List<Map<String, Object?>>? stops,
    ) async {
      final server = InProcessMockClient();
      final api = ApiClient(client: server);
      final id = await _book(api);
      final ride = server.rides[id]!;
      ride['status'] = 'in_trip';
      if (stops == null) {
        ride.remove('stops');
      } else {
        ride['stops'] = stops;
      }
      final realtime = ApiRideRealtime(
        api: api,
        pollInterval: const Duration(days: 1),
      );
      addTearDown(realtime.dispose);
      final events = <RideRealtimeEvent>[];
      final sub = realtime.subscribe(id).listen(events.add);
      addTearDown(sub.cancel);
      await realtime.reconnectAndResync(id);
      for (var i = 0; i < 200 && events.isEmpty; i++) {
        await pumpEventQueue();
      }
      expect(events, isNotEmpty);
      return events.last;
    }

    const stop = {'lat': 59.331, 'lng': 18.066, 'address': 'Stop 1'};

    test('open stop with away: paused', () async {
      final event = await eventFor([
        {
          ...stop,
          'arrivedAt': '2026-11-14T10:00:00Z',
          'away': {'since': '2026-11-14T10:02:00Z'},
        },
      ]);
      expect(event.stopAway, isTrue);
    });

    test('back (away gone, pausedSeconds kept): not paused', () async {
      final event = await eventFor([
        {
          ...stop,
          'arrivedAt': '2026-11-14T10:00:00Z',
          'pausedSeconds': 240,
          'pauseCount': 1,
        },
      ]);
      expect(event.stopAway, isFalse);
    });

    test('a left stop keeps away as a record: not paused', () async {
      final event = await eventFor([
        {
          ...stop,
          'arrivedAt': '2026-11-14T10:00:00Z',
          'leftAt': '2026-11-14T10:05:00Z',
          'away': {'since': '2026-11-14T10:02:00Z'},
        },
        {...stop, 'address': 'Stop 2'},
      ]);
      expect(event.stopAway, isFalse);
    });

    test('no stops: not paused', () async {
      expect((await eventFor(null)).stopAway, isFalse);
    });
  });

  test('tracking: stopAway follows the server, gone when back', () async {
    final feed = _Feed();
    final tracking = DriverTrackingController(
      realtime: feed,
      pickupLat: 59.33,
      pickupLng: 18.06,
      persistRideSnapshot: false,
    );
    addTearDown(() {
      tracking.dispose();
      feed.dispose();
    });
    tracking.start(rideId: 'c9b-trip');

    feed.add(RideStatus.tripInProgress);
    await _flush();
    expect(tracking.stopAway, isFalse);

    feed.add(RideStatus.tripInProgress, payload: {stopAwayKey: true});
    await _flush();
    expect(tracking.stopAway, isTrue);

    feed.add(RideStatus.tripInProgress);
    await _flush();
    expect(tracking.stopAway, isFalse);
  });
}

Future<String> _book(ApiClient api) async {
  const at = {
    'pickupLat': 59.3293,
    'pickupLng': 18.0686,
    'destinationLat': 59.3326,
    'destinationLng': 18.0649,
  };
  final quote =
      (await api.post(
            '/api/v1/quotes',
            body: {'rideType': 'economy', ...at},
          ))['quote']
          as Map;
  final created = await api.post(
    '/api/v1/rides',
    body: {
      'categoryId': 'economy',
      'fare': {'amountMinor': quote['totalMinor'], 'currency': 'SEK'},
      'paymentMethodId': 'card',
      'pickupAddress': 'Pickup',
      'destinationAddress': 'Destination',
      ...at,
      'quoteId': quote['id'],
      'quoteSignedPayload': quote['signedPayload'],
      'quoteExpiresAt': quote['expiresAt'],
      'quoteTotalMinor': quote['totalMinor'],
    },
  );
  return (created['ride'] as Map)['id'] as String;
}
