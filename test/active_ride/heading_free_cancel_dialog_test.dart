import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_icon_button.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live 5+5 run 2 (2026-11-08, frames 5-rider-cancel-p5 047, 050/051, 114):
/// the driver stood still for 3 min, the server's trip said
/// `headingCheck.freeCancel: true` (contract pickupWaiting.headingCheck
/// .riderCancel: not heading for notHeadingMinutes = free cancel), and
/// charged nothing; the cancel sheet still said "Att avboka nu kostar 35 kr".
///
/// Cause: the server changes `headingCheck` on its ETA tick without a new
/// version and without a projection event; the stream only carries the
/// tick's `location` event (no headingCheck). The app read the trip once
/// at open (freeCancel false) and never saw the change; a later read of the
/// same projection is a duplicate for the event gate (its `sequence` is the
/// last location event's). The sheet now reads the trip once when it opens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    L10n.use('en');
    AppScope.instance.ride
      ..rideId = null
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null
      ..restoreFromBackend(RideStatus.idle);
  });

  const live = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://x.invalid',
  );

  Map<String, Object?> projection(DateTime acceptedAt, {required bool free}) =>
      {
        'tripId': 'trp_1',
        'status': 'driver_to_pickup',
        'kind': 'live',
        'version': 3,
        // The resync cursor: the latest event, the ETA tick's location.
        'sequence': free ? 2 : 1,
        'updatedAt': acceptedAt.toIso8601String(),
        'acceptedAt': acceptedAt.toIso8601String(),
        'fare': {'amountMinor': 18400, 'currency': 'SEK'},
        'pickup': {'address': 'Vasagatan 1', 'lat': 59.3293, 'lng': 18.0686},
        'driver': {'driverId': 'd1', 'firstName': 'Anna'},
        'terms': {
          'currency': 'SEK',
          'freeWaitMin': 5,
          'waitPerMin': {'amountMinor': 500, 'currency': 'SEK'},
          'noShowAfterMin': 5,
          'noShowFee': {'amountMinor': 6500, 'currency': 'SEK'},
          'cancelRule': {'freeMin': 2, 'type': 'fixed', 'value': 3500},
          'cancelAfterArrivedIsNoShow': true,
          'maxPickupMoveMeters': 200,
        },
        'headingCheck': free
            ? {
                'heading': false,
                'checkedAt': acceptedAt
                    .add(const Duration(minutes: 3))
                    .toIso8601String(),
                'notHeadingSince': acceptedAt
                    .add(const Duration(seconds: 30))
                    .toIso8601String(),
                'freeCancel': true,
              }
            : {
                'heading': true,
                'checkedAt': acceptedAt.toIso8601String(),
                'freeCancel': false,
              },
      };

  String sse(Map<String, Object?> event) =>
      'id: ${event['sequence']}\ndata: ${jsonEncode(event)}\n\n';

  testWidgets('driver not heading for 2 min: the cancel sheet says no fee, '
      'as the server charges', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final acceptedAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 3, seconds: 20),
    );
    // What GET /trips/trp_1 answers: at open the driver is heading; later
    // (no event on the stream) the check says not heading, free cancel.
    var serverFree = false;
    final lines = StreamController<List<int>>();
    addTearDown(lines.close);
    final realtime = ApiRideRealtime(
      api: ApiClient(
        env: live,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/events')) {
            return http.StreamedResponse(lines.stream, 200);
          }
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(jsonEncode(projection(acceptedAt, free: serverFree))),
            ),
            200,
          );
        }),
      ),
    );
    addTearDown(realtime.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Vasagatan 1',
          destinationAddress: 'Kungsgatan 2',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: 184,
          currency: 'SEK',
          paymentMethod: 'Cash',
          rideId: 'trp_1',
          driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
          realtime: realtime,
          persistRideSnapshot: false,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // The ETA tick: a location event, no version change, no headingCheck.
    lines.add(
      utf8.encode(
        sse({
          'eventId': 'ev-2',
          'tripId': 'trp_1',
          'sequence': 2,
          'version': 3,
          'kind': 'location',
          'occurredAt': DateTime.now().toUtc().toIso8601String(),
          'serverTime': DateTime.now().toUtc().toIso8601String(),
          'location': {
            'lat': 59.34,
            'lng': 18.05,
            'accuracy': 5,
            'measuredAt': DateTime.now().toUtc().toIso8601String(),
          },
          'etaSeconds': 240,
        }),
      ),
    );
    serverFree = true;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final close = tester.widget<MoveraIconButton>(
      find.ancestor(
        of: find.byIcon(Icons.close_rounded).first,
        matching: find.byType(MoveraIconButton),
      ),
    );
    close.onPressed();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final fee = L10n.current.cancelCostsNow(
      formatMoney(const Money(3500, 'SEK')),
    );
    expect(find.text(fee), findsNothing, reason: 'the server charges nothing');
    expect(find.text(L10n.current.noFeeToCancel), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('driver heading: the cancel sheet still says the fee', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final acceptedAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 3, seconds: 20),
    );
    final lines = StreamController<List<int>>();
    addTearDown(lines.close);
    final realtime = ApiRideRealtime(
      api: ApiClient(
        env: live,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/events')) {
            return http.StreamedResponse(lines.stream, 200);
          }
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(jsonEncode(projection(acceptedAt, free: false))),
            ),
            200,
          );
        }),
      ),
    );
    addTearDown(realtime.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Vasagatan 1',
          destinationAddress: 'Kungsgatan 2',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: 184,
          currency: 'SEK',
          paymentMethod: 'Cash',
          rideId: 'trp_1',
          driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
          realtime: realtime,
          persistRideSnapshot: false,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final close = tester.widget<MoveraIconButton>(
      find.ancestor(
        of: find.byIcon(Icons.close_rounded).first,
        matching: find.byType(MoveraIconButton),
      ),
    );
    close.onPressed();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text(
        L10n.current.cancelCostsNow(formatMoney(const Money(3500, 'SEK'))),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  test('a re-read of the same projection does not reach the screen: the '
      'event gate takes it as a duplicate of the location tick', () async {
    final acceptedAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 3),
    );
    var serverFree = false;
    final lines = StreamController<List<int>>();
    addTearDown(lines.close);
    final realtime = ApiRideRealtime(
      api: ApiClient(
        env: live,
        client: MockClient.streaming((request, _) async {
          if (request.url.path.endsWith('/events')) {
            return http.StreamedResponse(lines.stream, 200);
          }
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(jsonEncode(projection(acceptedAt, free: serverFree))),
            ),
            200,
          );
        }),
      ),
    );
    addTearDown(realtime.dispose);
    final events = <RideRealtimeEvent>[];
    final sub = realtime.subscribe('trp_1').listen(events.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events.last.headingFreeCancel, isFalse);
    lines.add(
      utf8.encode(
        sse({
          'eventId': 'ev-2',
          'tripId': 'trp_1',
          'sequence': 2,
          'version': 3,
          'kind': 'location',
          'serverTime': DateTime.now().toUtc().toIso8601String(),
          'location': {'lat': 59.34, 'lng': 18.05},
        }),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events.last.headingFreeCancel, isNull, reason: 'tick: no check');
    serverFree = true;
    final count = events.length;
    await realtime.reconnectAndResync('trp_1');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events, hasLength(count), reason: 'the re-read is dropped');
    // The sheet's own read sees what the server says now.
    expect(await realtime.readHeadingFreeCancel('trp_1'), isTrue);
  });
}
