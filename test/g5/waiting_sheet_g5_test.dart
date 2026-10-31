import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/trip_terms.dart';
import 'package:movera_rider/core/realtime/realtime_gate.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/presentation/driver_arrived_sheet.dart';
import 'package:movera_rider/features/active_ride/presentation/trip_terms_note.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_fee_counter.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_for_driver.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Feed implements RideRealtime {
  final _events = StreamController<RideRealtimeEvent>.broadcast();
  int _sequence = 0;

  void add(
    RideStatus status, {
    RealtimeKind? kind,
    double? lat,
    double? lng,
    Map<String, Object?> payload = const {},
  }) {
    _sequence += 1;
    _events.add(
      RideRealtimeEvent(
        tripId: 'g5-wait',
        status: status,
        sequence: _sequence,
        version: _sequence,
        kind: kind,
        driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
        latitude: lat,
        longitude: lng,
        locationAt: lat == null ? null : DateTime.now(),
        payload: payload,
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

/// Driver group 5 on the Waiting screen (contract v0.18.7): the server's
/// ETA with the distance, the waiting TIME only on the sheet with the
/// prices in the Terms (from the trip's `terms`, in its currency), the
/// trip's fare as the total from boarding (Q5), and a pickup the server
/// moved (`pickup_moved`).
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

  tearDown(() => L10n.use('en'));

  final parisTerms = <String, Object?>{
    'currency': 'EUR',
    'freeWaitMin': 3,
    'waitPerMin': {'amountMinor': 110, 'currency': 'EUR'},
    'noShowAfterMin': 3,
    'noShowFee': {'amountMinor': 800, 'currency': 'EUR'},
    'cancelRule': {
      'freeMin': 2,
      'type': 'fixed',
      'value': 500,
      'min': null,
      'max': null,
    },
    'cancelAfterArrivedIsNoShow': true,
    'maxPickupMoveMeters': 200,
  };

  Future<_Feed> pump(
    WidgetTester tester, {
    String currency = 'SEK',
    double price = 86,
  }) async {
    // A tall phone, so the whole Waiting sheet is on screen.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final feed = _Feed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WaitingForDriver(
          pickupAddress: 'Vasagatan 1',
          destinationAddress: 'Kungsgatan 2',
          pickupPosition: const LatLng(59.3293, 18.0686),
          destinationPosition: const LatLng(59.3326, 18.0649),
          rideType: 'Movera',
          price: price,
          currency: currency,
          paymentMethod: 'Cash',
          rideId: 'g5-wait',
          driver: const MatchedDriver(id: 'd1', firstName: 'Anna'),
          realtime: feed,
          persistRideSnapshot: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return feed;
  }

  testWidgets('the headline is the server ETA with the road distance', (
    tester,
  ) async {
    final feed = await pump(tester);
    feed.add(
      RideStatus.driverArriving,
      lat: 59.34,
      lng: 18.05,
      payload: {
        etaKey: {
          'etaSeconds': 250,
          'distanceMeters': 1234,
          'target': 'pickup',
          'at': DateTime.now().toUtc().toIso8601String(),
          'source': 'osrm',
        },
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Arrives in 5 min · 1.2 km'), findsWidgets);
    expect(find.textContaining('Updating driver location'), findsNothing);
  });

  testWidgets(
    'driver waiting: the sheet shows the waiting time only; the Terms row '
    'opens the euro prices from the trip terms',
    (tester) async {
      final feed = await pump(tester, currency: 'EUR', price: 18);
      feed.add(
        RideStatus.driverWaiting,
        lat: 59.3293,
        lng: 18.0686,
        payload: {
          waitingArrivedAtKey: DateTime.now().toUtc().toIso8601String(),
          termsKey: parisTerms,
          waitingChargedSoFarKey: {'amountMinor': 0, 'currency': 'EUR'},
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      // The arrived sheet, when announced on top, is closed first.
      if (find.byType(DriverArrivedSheet).evaluate().isNotEmpty) {
        await tester.tap(
          find.descendant(
            of: find.byType(DriverArrivedSheet),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
      }
      expect(find.byKey(WaitingFeeCounter.counterKey), findsOneWidget);
      expect(find.textContaining('Free waiting · '), findsOneWidget);
      // Texting the driver stays possible after the arrival.
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
      expect(
        find.text('Waiting time is charged after the free minutes'),
        findsOneWidget,
      );
      // No price in the counter: the sheet shows the time only.
      expect(
        find.descendant(
          of: find.byKey(WaitingFeeCounter.counterKey),
          matching: find.textContaining('€'),
        ),
        findsNothing,
      );
      // The prices live behind the Terms row, from the trip's own terms
      // (euro: the Paris zone's pricing, nothing of the app's own).
      final row = tester.widget<TripTermsNote>(find.byType(TripTermsNote));
      expect(row.lines.lines, [
        'Free waiting 3 min, then 1,10 € per minute',
        'If you do not show up within 3 min after the driver arrives, a 8,00 € fee applies',
        'Cancelling after the driver has arrived counts as a no-show',
        'You can move the pickup at most 200 m after booking',
      ]);
    },
  );

  testWidgets('the Terms row opens the terms as a sheet', (tester) async {
    final lines = TripTermsLines.fromTerms(TripTerms.fromWire(parisTerms)!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TripTermsNote(lines: lines)),
      ),
    );
    await tester.tap(find.byKey(TripTermsNote.noteKey));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.byKey(TripTermsNote.sheetKey), findsOneWidget);
    expect(find.text('Waiting and cancellation'), findsWidgets);
    expect(
      find.text('Free waiting 3 min, then 1,10 € per minute'),
      findsOneWidget,
    );
    expect(
      find.text('You can move the pickup at most 200 m after booking'),
      findsOneWidget,
    );
  });

  testWidgets('from boarding the total is the trip fare incl. waiting (Q5)', (
    tester,
  ) async {
    final feed = await pump(tester, price: 86);
    feed.add(
      RideStatus.tripInProgress,
      lat: 59.331,
      lng: 18.066,
      payload: {
        fareKey: {'amountMinor': 10100, 'currency': 'SEK'},
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    final line = tester.widget<Text>(
      find.byKey(const ValueKey<String>('trip-summary-line')),
    );
    expect(line.data, contains('101 kr'));
    expect(line.data, isNot(contains('86 kr')));
  });

  testWidgets('a pickup_moved event moves the pickup and says so', (
    tester,
  ) async {
    final feed = await pump(tester);
    feed.add(
      RideStatus.driverArriving,
      kind: RealtimeKind.pickupMoved,
      payload: {
        pickupKey: {'address': 'Vasagatan 9', 'lat': 59.3302, 'lng': 18.069},
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Pickup moved'), findsOneWidget);
    expect(find.textContaining('Vasagatan 9'), findsWidgets);
  });
}
