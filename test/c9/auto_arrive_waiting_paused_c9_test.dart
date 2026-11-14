import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_fee_counter.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Job C9 (contract v0.18.93 §91, `contract.json#autoArrive`; owner
/// 2026-11-02 review Q3 "Both: auto + button", Rules
/// decisions/driver-g7.md:83-84): while the driver is more than 200 m from
/// the pickup the server stops the waiting clock (`waiting.away.since`).
/// The rider's driver-arrived sheet shows the server's clock: it stands
/// still and says so, and goes on from the server's moved freeUntil. The
/// time only (group 6 decision 4).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  final arrived = DateTime(2026, 11, 14, 10);

  Future<void> pump(
    WidgetTester tester,
    DateTime now, {
    required DateTime freeUntil,
    DateTime? pausedSince,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WaitingFeeCounter(
          since: arrived,
          freeWaitMin: 5,
          perMin: const Money(1226, 'SEK'),
          freeUntil: freeUntil,
          pausedSince: pausedSince,
          clock: () => now,
        ),
      ),
    ),
  );

  test('texts.riderPaused is the contract text in sv, fr and en', () {
    final contract =
        jsonDecode(File('contracts/contract.json').readAsStringSync())
            as Map<String, dynamic>;
    final texts =
        (contract['autoArrive'] as Map)['texts']['riderPaused'] as Map;
    for (final lang in ['sv', 'fr', 'en']) {
      expect(
        lookupAppLocalizations(Locale(lang)).waitingPausedDriverAway,
        texts[lang],
        reason: lang,
      );
    }
  });

  testWidgets('away since 10:02: the free time left stands at 3:00 with '
      'the paused line, at 10:04 and at 10:30', (tester) async {
    final freeUntil = DateTime(2026, 11, 14, 10, 5);
    final since = DateTime(2026, 11, 14, 10, 2);
    for (final now in [
      DateTime(2026, 11, 14, 10, 4),
      DateTime(2026, 11, 14, 10, 30),
    ]) {
      await pump(tester, now, freeUntil: freeUntil, pausedSince: since);
      expect(find.text(L10n.current.freeWaitingLeft('3:00')), findsOneWidget);
      expect(find.text(L10n.current.waitingPausedDriverAway), findsOneWidget);
      expect(find.text(L10n.current.waitingChargedAfterFree), findsNothing);
    }
  });

  testWidgets('paid waiting stands still too (away after the free wait)', (
    tester,
  ) async {
    await pump(
      tester,
      DateTime(2026, 11, 14, 10, 20),
      freeUntil: DateTime(2026, 11, 14, 10, 5),
      pausedSince: DateTime(2026, 11, 14, 10, 7),
    );
    expect(
      find.text(L10n.current.waitingTimeOverFree('2:00', '5')),
      findsOneWidget,
    );
    expect(find.text(L10n.current.waitingPausedDriverAway), findsOneWidget);
  });

  testWidgets('back: the clock goes on from the server\'s moved freeUntil '
      '(6 min stopped → 10:11)', (tester) async {
    await pump(
      tester,
      DateTime(2026, 11, 14, 10, 9),
      freeUntil: DateTime(2026, 11, 14, 10, 11),
    );
    expect(find.text(L10n.current.freeWaitingLeft('2:00')), findsOneWidget);
    expect(find.text(L10n.current.waitingPausedDriverAway), findsNothing);
  });

  test(
    'waiting.away.since reaches the app; none when the clock runs',
    () async {
      final server = InProcessMockClient();
      final api = ApiClient(client: server);
      final id = await _book(api);
      await api.post('/api/v1/rides/$id/status', body: {'status': 'arrived'});
      final ride = server.rides[id]!;
      (ride['waiting'] as Map)['away'] = {'since': '2026-11-14T10:02:00Z'};
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
      expect(
        events.last.waitingAwaySince,
        WireTime.tryParse('2026-11-14T10:02:00Z'),
      );
    },
  );
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
