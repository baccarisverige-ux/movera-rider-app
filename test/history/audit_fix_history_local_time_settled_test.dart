import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/history/data/ride_history_repositories.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-36: History held book-now times as UTC DateTimes, and every
/// formatter reads the fields as they are, so times showed in UTC.
/// rider-37: fully settled (`closed`) and payment-failed trips were dropped
/// from History.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );

  RideSnapshot snapshot(String rideId) => RideSnapshot(
    status: RideStatus.tripCompleted,
    savedAt: DateTime.now(),
    createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
    pickupAddress: 'Stockholm Central',
    destinationAddress: 'Arlanda Airport',
    pickupLat: 59.3293,
    pickupLng: 18.0686,
    destinationLat: 59.6519,
    destinationLng: 17.9186,
    rideType: 'Movera',
    price: 319,
    paymentMethod: 'Apple Pay',
    rideId: rideId,
  );

  Map<String, dynamic> trip(
    String id, {
    String status = 'completed',
    String? paymentStatus,
    String? ratingStatus,
  }) => {
    'id': id,
    'status': status,
    if (paymentStatus != null) 'paymentStatus': paymentStatus,
    if (ratingStatus != null) 'ratingStatus': ratingStatus,
    'version': 3,
    'updatedAt': '2026-10-14T09:00:00.000Z',
    'categoryId': 'comfort',
    'paymentMethodId': 'cash',
    'price': 319,
    'pickupAddress': 'Stockholm Central',
    'pickupLat': 59.3293,
    'pickupLng': 18.0686,
    'destinationAddress': 'Arlanda Airport',
    'destinationLat': 59.6519,
    'destinationLng': 17.9186,
  };

  Future<List<Reservation>> serverHistory(
    Map<String, Map<String, dynamic>> trips,
  ) {
    final mock = InProcessMockClient();
    mock.rides.addAll(trips);
    return ApiRideHistoryRepository(
      api: ApiClient(client: mock, env: demo),
    ).loadOnDemand();
  }

  group('rider-36: History shows the rider\'s local time', () {
    test('a ride ended at a UTC instant is held in local time', () {
      final endedUtc = DateTime.utc(2026, 6, 10, 12, 30);
      final record = OnDemandRideHistoryStore.recordFor(
        snapshot('ride-utc'),
        terminalStatus: RideStatus.paymentFinalized,
        endedAt: endedUtc,
      )!;
      expect(record.scheduledPickupAt.isUtc, isFalse);
      expect(record.scheduledPickupAt, endedUtc.toLocal());
      final local = endedUtc.toLocal();
      expect(
        ReservationFormat.time(record.scheduledPickupAt),
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}',
      );
    });

    test('a server trip is listed in local time', () async {
      final history = await serverHistory({
        'ride_a': trip('ride_a', status: 'paymentFinalized'),
      });
      final at = history.single.scheduledPickupAt;
      expect(at.isUtc, isFalse);
      expect(at, DateTime.utc(2026, 10, 14, 9).toLocal());
    });

    test('archive stores UTC and reads back local time', () async {
      final endedUtc = DateTime.utc(2026, 10, 14, 12, 30);
      final ride = snapshot('ride-roundtrip');
      await OnDemandRideHistoryStore.archive(
        ride,
        terminalStatus: RideStatus.paymentFinalized,
        endedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      // A second archive of the same ride replaces the first (dedup by id).
      await OnDemandRideHistoryStore.archive(
        ride,
        terminalStatus: RideStatus.paymentFinalized,
        endedAt: endedUtc,
      );
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(prefs.getString(OnDemandRideHistoryStore.key)!);
      expect(
        (raw as List).single['scheduledPickupAt'],
        endedUtc.toIso8601String(),
      );
      final read = await OnDemandRideHistoryStore.read();
      expect(read.single.scheduledPickupAt.isUtc, isFalse);
      expect(read.single.scheduledPickupAt, endedUtc.toLocal());
    });

    test('a record an older build stored in UTC reads back local', () async {
      final endedUtc = DateTime.now().toUtc().subtract(const Duration(days: 1));
      final record = OnDemandRideHistoryStore.recordFor(
        snapshot('ride-old'),
        terminalStatus: RideStatus.paymentFinalized,
        endedAt: endedUtc,
      )!;
      final stored = record.toJson()
        ..['scheduledPickupAt'] = endedUtc.toIso8601String();
      SharedPreferences.setMockInitialValues(<String, Object>{
        OnDemandRideHistoryStore.key: jsonEncode([stored]),
      });
      final read = await OnDemandRideHistoryStore.read();
      expect(read.single.scheduledPickupAt.isUtc, isFalse);
      expect(read.single.scheduledPickupAt, endedUtc.toLocal());
    });
  });

  group('rider-37: settled and payment-failed trips stay in History', () {
    test('a closed trip is a completed History ride', () {
      final record = OnDemandRideHistoryStore.recordFor(
        snapshot('ride-closed'),
        terminalStatus: RideStatus.closed,
      );
      expect(record, isNotNull);
      expect(record!.status, ReservationStatus.completed);
      expect(ReservationFormat.historyStatus(record), 'Completed');
    });

    test('server trips paid and rated or skipped are listed', () async {
      final history = await serverHistory({
        'ride_rated': trip(
          'ride_rated',
          paymentStatus: 'captured',
          ratingStatus: 'submitted',
        ),
        'ride_skipped': trip(
          'ride_skipped',
          paymentStatus: 'captured',
          ratingStatus: 'skipped',
        ),
      });
      expect(history.map((r) => r.reservationId).toSet(), {
        'ondemand-ride_rated',
        'ondemand-ride_skipped',
      });
      for (final ride in history) {
        expect(ride.status, ReservationStatus.completed);
        expect(ReservationFormat.historyStatus(ride), 'Completed');
      }
    });

    test('a payment-failed server trip is listed as Payment failed', () async {
      final history = await serverHistory({
        'ride_unpaid': trip('ride_unpaid', paymentStatus: 'failed'),
      });
      final ride = history.single;
      expect(ride.reservationId, 'ondemand-ride_unpaid');
      expect(ride.status, ReservationStatus.completed);
      expect(ReservationFormat.historyStatus(ride), 'Payment failed');
    });

    test('Payment failed survives the device archive', () async {
      await OnDemandRideHistoryStore.archive(
        snapshot('ride-unpaid-local'),
        terminalStatus: RideStatus.paymentFailed,
      );
      final ride = (await OnDemandRideHistoryStore.read()).single;
      expect(ride.status, ReservationStatus.completed);
      expect(ReservationFormat.historyStatus(ride), 'Payment failed');
    });

    testWidgets('the History card shows the Payment failed chip', (
      tester,
    ) async {
      final record = OnDemandRideHistoryStore.recordFor(
        snapshot('ride-unpaid-card'),
        terminalStatus: RideStatus.paymentFailed,
      );
      expect(record, isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReservationHistoryCard(ride: record!, onTap: () {}),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('history-status-chip')),
          matching: find.text('Payment failed'),
        ),
        findsOneWidget,
      );
    });
  });
}
