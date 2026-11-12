import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/realtime/api_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/active_ride/application/active_ride_controller.dart';
import 'package:movera_rider/features/driver_arriving/application/driver_tracking_controller.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G33 (owner 2026-11-12 ~16:45 "Yes, clear line", ~17:30 "OK"; contract
/// v0.18.78 `finish.payInCarLine` + `finish.paymentMethods.texts
/// .payDriverInCar`): at the end of a trip paid in the car the rider's
/// completion screen says "Pay the driver {amount} in the car", with
/// {amount} = TripProjection.finish.cashToCollect (the CompletePreview
/// .cashDue the driver collected), after a reload the receipt's cashPaid.
/// Not for card / Apple Pay / wallet trips, not when the amount is 0, not
/// after an early end.
class _Realtime extends RideRealtime {
  final c = StreamController<RideRealtimeEvent>.broadcast(sync: true);
  @override
  bool get supportsRiderSignals => false;
  @override
  Stream<RideRealtimeEvent> subscribe(String rideId) => c.stream;
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
  void dispose() => c.close();
}

RideSnapshot _ride({
  String paymentMethod = 'Cash',
  String currency = 'SEK',
  double price = 217,
  RideStatus status = RideStatus.tripCompleted,
  String rideId = 'trp_g33',
}) => RideSnapshot(
  status: status,
  savedAt: DateTime.now(),
  pickupAddress: 'Södertälje centrum',
  destinationAddress: 'Stockholm Central Station',
  pickupLat: 59.1955,
  pickupLng: 17.6253,
  destinationLat: 59.33,
  destinationLng: 18.0587,
  rideType: 'Movera',
  price: price,
  currency: currency,
  paymentMethod: paymentMethod,
  rideId: rideId,
  version: 9,
);

const _line = ValueKey('completion-pay-in-car');

Future<void> _pump(
  WidgetTester tester, {
  Future<ServerReceipt?> Function(String)? receipt,
  EndedEarlyTrip? endedEarly,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final realtime = _Realtime();
  addTearDown(realtime.dispose);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(1200, 2400),
      builder: (_, _) => MaterialApp(
        home: RideCompleted(
          status: RideStatus.paymentFinalized,
          rideId: 'trp_g33',
          realtime: realtime,
          persistOnDemandState: false,
          showConnectionBanner: false,
          endedEarly: endedEarly,
          receiptLoader: receipt ?? (_) async => null,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

String? _lineText(WidgetTester tester) {
  final found = find.byKey(_line);
  if (found.evaluate().isEmpty) return null;
  return tester.widget<Text>(found).data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    LastCompletedRide.clear();
    L10n.use('en');
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });
  tearDown(() {
    LastCompletedRide.clear();
    L10n.use('en');
  });

  group('G33 wire', () {
    testWidgets('G33: the poll puts finish.cashToCollect on the event', (
      tester,
    ) async {
      final rt = ApiRideRealtime(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'tripId': 'trp_g33',
                'status': 'completed',
                'version': 12,
                'updatedAt': '2026-11-12T18:00:00Z',
                'paymentMethod': 'cash',
                'fare': {'amountMinor': 21700, 'currency': 'SEK'},
                'finish': {
                  'endedEarly': false,
                  'total': {'amountMinor': 21700, 'currency': 'SEK'},
                  'cashToCollect': {'amountMinor': 16700, 'currency': 'SEK'},
                  'ratingAllowed': true,
                },
              }),
              200,
            ),
          ),
          env: AppEnv.current,
        ),
        pollInterval: const Duration(seconds: 2),
      );
      addTearDown(rt.dispose);
      final events = <RideRealtimeEvent>[];
      final sub = rt.subscribe('trp_g33').listen(events.add);
      addTearDown(sub.cancel);
      await tester.pump();
      await rt.reconnectAndResync('trp_g33');
      await tester.pump();

      expect(events, isNotEmpty);
      expect(events.last.cashToCollect, const Money(16700, 'SEK'));
      expect(events.last.finishedEarly, isFalse);
      rt.dispose();
    });

    test('G33: a driver early end is marked on the event', () {
      final event = RideRealtimeEvent(
        tripId: 'trp_g33',
        status: RideStatus.tripCompleted,
        sequence: 12,
        payload: {
          cashToCollectKey: {'amountMinor': 9000, 'currency': 'SEK'},
          finishedEarlyKey: true,
        },
      );
      expect(event.cashToCollect, const Money(9000, 'SEK'));
      expect(event.finishedEarly, isTrue);
    });

    test(
      'G33: the tracker keeps the last cashToCollect the wire carried',
      () async {
        await RideSnapshotStore.save(_ride(status: RideStatus.tripInProgress));
        final realtime = _Realtime();
        addTearDown(realtime.dispose);
        final ride = RideSession(rideId: 'trp_g33')
          ..status = RideStatus.tripInProgress
          ..authoritativeVersion = 9;
        final controller = DriverTrackingController(
          realtime: realtime,
          pickupLat: 59.1955,
          pickupLng: 17.6253,
          ride: ride,
        );
        addTearDown(controller.dispose);
        controller.start(
          rideId: 'trp_g33',
          initialStatus: RideStatus.tripInProgress,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(controller.cashToCollect, isNull);

        realtime.c.add(
          RideRealtimeEvent(
            tripId: 'trp_g33',
            status: RideStatus.tripCompleted,
            sequence: 12,
            version: 12,
            serverTime: DateTime.utc(2026, 11, 12, 18),
            payload: {
              fareKey: {'amountMinor': 21700, 'currency': 'SEK'},
              cashToCollectKey: {'amountMinor': 16700, 'currency': 'SEK'},
            },
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(controller.status, RideStatus.tripCompleted);
        expect(controller.cashToCollect, const Money(16700, 'SEK'));
        expect(controller.finishedEarly, isFalse);
      },
    );

    test('G33: completion remembers cashToCollect for the summary', () async {
      final snapshot = _ride(status: RideStatus.tripInProgress);
      await RideSnapshotStore.save(snapshot);
      AppScope.instance.ride
        ..rideId = snapshot.rideId
        ..status = RideStatus.tripInProgress;

      await ActiveRideController().markCompleted(
        RideStatus.tripCompleted,
        charged: const Money(21700, 'SEK'),
        cashToCollect: const Money(16700, 'SEK'),
      );

      expect(LastCompletedRide.cashToCollect, const Money(16700, 'SEK'));
      expect(LastCompletedRide.finishedEarly, isFalse);
      // A later payment status keeps it (persistCompletedStatus).
      await ActiveRideController().persistCompletedStatus(
        RideStatus.paymentFinalized,
        rideId: 'trp_g33',
      );
      expect(LastCompletedRide.cashToCollect, const Money(16700, 'SEK'));
    });

    test('G33: an amount in another currency is not this trip\'s', () async {
      final snapshot = _ride(status: RideStatus.tripInProgress);
      await RideSnapshotStore.save(snapshot);
      AppScope.instance.ride
        ..rideId = snapshot.rideId
        ..status = RideStatus.tripInProgress;

      await ActiveRideController().markCompleted(
        RideStatus.tripCompleted,
        cashToCollect: const Money(500, 'EUR'),
      );
      expect(LastCompletedRide.cashToCollect, isNull);
    });
  });

  group('G33 completion line', () {
    testWidgets(
      "G33: a completed cash trip shows 'Pay the driver 123 kr in the car'",
      (tester) async {
        LastCompletedRide.remember(
          _ride(price: 123),
          cashToCollect: const Money(12300, 'SEK'),
        );
        await _pump(tester);
        expect(_lineText(tester), 'Pay the driver 123 kr in the car');
      },
    );

    testWidgets('G33: the amount is finish.cashToCollect, not the fare', (
      tester,
    ) async {
      // Fare 217 kr, 50 kr from the wallet: the driver collects 167 kr.
      LastCompletedRide.remember(
        _ride(),
        charged: const Money(21700, 'SEK'),
        cashToCollect: const Money(16700, 'SEK'),
      );
      await _pump(tester);
      expect(_lineText(tester), 'Pay the driver 167 kr in the car');
    });

    testWidgets('G33: no line when cashToCollect is 0 (the wallet paid all)', (
      tester,
    ) async {
      LastCompletedRide.remember(_ride(), cashToCollect: const Money(0, 'SEK'));
      await _pump(tester);
      expect(find.byKey(_line), findsNothing);
    });

    testWidgets('G33: no line for a card, Apple Pay or wallet trip', (
      tester,
    ) async {
      for (final method in ['Card', 'Apple Pay', 'Wallet']) {
        LastCompletedRide.remember(
          _ride(paymentMethod: method),
          cashToCollect: const Money(12300, 'SEK'),
        );
        await _pump(tester);
        expect(find.byKey(_line), findsNothing, reason: method);
      }
    });

    testWidgets('G33: no line after a driver early end (only "You pay")', (
      tester,
    ) async {
      LastCompletedRide.remember(
        _ride(),
        cashToCollect: const Money(9000, 'SEK'),
        finishedEarly: true,
      );
      await _pump(tester);
      expect(find.byKey(_line), findsNothing);
    });

    testWidgets('G33: no line on the rider early-end screen', (tester) async {
      LastCompletedRide.remember(
        _ride(),
        charged: const Money(9000, 'SEK'),
        endedEarly: true,
        cashToCollect: const Money(9000, 'SEK'),
      );
      await _pump(
        tester,
        endedEarly: const EndedEarlyTrip(
          rideId: 'trp_g33',
          charged: Money(9000, 'SEK'),
        ),
      );
      expect(find.byKey(_line), findsNothing);
      expect(find.text('You pay 90 kr'), findsOneWidget);
    });

    testWidgets('G33: another ride\'s amount is never shown', (tester) async {
      LastCompletedRide.remember(
        _ride(rideId: 'trp_other'),
        cashToCollect: const Money(12300, 'SEK'),
      );
      await _pump(tester);
      expect(find.byKey(_line), findsNothing);
    });

    testWidgets("G33: fr 'Payez 123 kr au chauffeur', sv 'Betala föraren "
        "123 kr i bilen'", (tester) async {
      LastCompletedRide.remember(
        _ride(price: 123),
        cashToCollect: const Money(12300, 'SEK'),
      );
      L10n.use('fr');
      await _pump(tester);
      expect(_lineText(tester), 'Payez 123 kr au chauffeur');
      L10n.use('sv');
      await tester.pumpWidget(const SizedBox());
      await _pump(tester);
      expect(_lineText(tester), 'Betala föraren 123 kr i bilen');
    });

    testWidgets("G33: TND is '12.350 DT' (moneyDisplay §81)", (tester) async {
      LastCompletedRide.remember(
        _ride(currency: 'TND', price: 12.35),
        cashToCollect: const Money(12350, 'TND'),
      );
      await _pump(tester);
      expect(_lineText(tester), 'Pay the driver 12.350 DT in the car');
    });

    testWidgets(
      "G33: after a reload (no trip event) the line comes from the receipt's "
      'cashPaid',
      (tester) async {
        // The restore path remembers the snapshot only.
        LastCompletedRide.remember(_ride());
        await _pump(
          tester,
          receipt: (id) async => ServerReceipt.tryParse({
            'tripId': id,
            'paymentMethod': 'cash',
            'total': {'amountMinor': 21700, 'currency': 'SEK'},
            'walletPaid': {'amountMinor': 5000, 'currency': 'SEK'},
            'cashPaid': {'amountMinor': 16700, 'currency': 'SEK'},
            'endedEarly': false,
          }),
        );
        expect(_lineText(tester), 'Pay the driver 167 kr in the car');
      },
    );

    testWidgets('G33: the receipt fallback keeps the rules (card, 0, early '
        'end)', (tester) async {
      final receipts = <Map<String, dynamic>>[
        {
          'paymentMethod': 'card',
          'cashPaid': {'amountMinor': 16700, 'currency': 'SEK'},
          'endedEarly': false,
        },
        {
          'paymentMethod': 'cash',
          'cashPaid': {'amountMinor': 0, 'currency': 'SEK'},
          'endedEarly': false,
        },
        {
          'paymentMethod': 'cash',
          'cashPaid': {'amountMinor': 9000, 'currency': 'SEK'},
          'endedEarly': true,
          'endedBy': 'driver',
        },
      ];
      for (final body in receipts) {
        LastCompletedRide.remember(_ride());
        await _pump(
          tester,
          receipt: (id) async =>
              ServerReceipt.tryParse({'tripId': id, ...body}),
        );
        expect(find.byKey(_line), findsNothing, reason: '$body');
      }
    });

    test('G33: the receipt parses cashPaid and paymentMethod', () {
      final receipt = ServerReceipt.tryParse({
        'tripId': 'trp_g33',
        'paymentMethod': 'cash',
        'cashPaid': {'amountMinor': 16700, 'currency': 'SEK'},
      })!;
      expect(receipt.cashPaid, const Money(16700, 'SEK'));
      expect(receipt.paymentMethod, 'cash');
    });
  });

  group('G33 mock and contract', () {
    test('G33: the stand-in server\'s completed cash trip carries '
        'finish.cashToCollect = fare − wallet part', () async {
      final server = InProcessMockClient();
      final api = ApiClient(client: server);
      final quote =
          (await api.post(
                '/api/v1/quotes',
                body: {
                  'rideType': 'movera',
                  'pickupLat': 59.3293,
                  'pickupLng': 18.0686,
                  'destinationLat': 59.3326,
                  'destinationLng': 18.0649,
                },
              ))['quote']
              as Map;
      Future<Map<String, dynamic>> book(String method, int wallet) async {
        final created = await api.post(
          '/api/v1/rides',
          body: {
            'categoryId': 'movera',
            'price': (quote['totalMinor'] as int) / 100,
            'paymentMethodId': method,
            'useWalletFirst': wallet > 0,
            'walletAmountMinor': wallet,
            'pickupAddress': 'Pickup',
            'destinationAddress': 'Destination',
            'pickupLat': 59.3293,
            'pickupLng': 18.0686,
            'destinationLat': 59.3326,
            'destinationLng': 18.0649,
            'quoteId': quote['id'],
            'quoteSignedPayload': quote['signedPayload'],
            'quoteExpiresAt': quote['expiresAt'],
            'quoteTotalMinor': quote['totalMinor'],
          },
        );
        final id = (created['ride'] as Map)['id'] as String;
        return Map<String, dynamic>.from(
          (await api.post(
                '/api/v1/rides/$id/status',
                body: {'status': 'completed'},
              ))['ride']
              as Map,
        );
      }

      final total = quote['totalMinor'] as int;
      final cash = await book('cash', 0);
      final finish = cash['finish'] as Map;
      expect(Money.fromWire(finish['cashToCollect'])?.amountMinor, total);
      expect(finish['endedEarly'], isFalse);

      final part = await book('cash', 1000);
      expect(
        Money.fromWire((part['finish'] as Map)['cashToCollect'])?.amountMinor,
        total - 1000,
      );

      final card = await book('card_visa', 0);
      expect(
        Money.fromWire((card['finish'] as Map)['cashToCollect'])?.amountMinor,
        0,
      );
    });

    test('G33: payDriverInCar equals contract.json#finish.paymentMethods'
        '.texts.payDriverInCar (en, fr, sv)', () {
      final contract =
          jsonDecode(File('contracts/contract.json').readAsStringSync())
              as Map<String, dynamic>;
      final finish = contract['finish'] as Map<String, dynamic>;
      final texts =
          (finish['paymentMethods'] as Map<String, dynamic>)['texts']
              as Map<String, dynamic>;
      expect(finish['payInCarLine'], isA<String>());
      for (final lang in ['en', 'fr', 'sv']) {
        final arb =
            jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
                as Map<String, dynamic>;
        expect(
          arb['payDriverInCar'],
          (texts['payDriverInCar'] as Map)[lang],
          reason: lang,
        );
      }
    });
  });
}
