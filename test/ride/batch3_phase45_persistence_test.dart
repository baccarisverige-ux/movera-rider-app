import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/history/data/on_demand_ride_history_store.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot _snapshot(String id, {DateTime? createdAt}) => RideSnapshot(
      status: RideStatus.tripInProgress,
      savedAt: DateTime.utc(2026, 9, 24, 12),
      createdAt: createdAt,
      pickupAddress: 'Pickup',
      destinationAddress: 'Destination',
      pickupLat: 59.33,
      pickupLng: 18.06,
      destinationLat: 59.34,
      destinationLng: 18.07,
      rideType: 'Movera',
      price: 100,
      paymentMethod: 'Apple Pay',
      rideId: id,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    await RideSnapshotStore.clear();
    await OnDemandRideHistoryStore.clear();
  });

  test('v1 snapshot migrates without manufacturing creation time', () {
    final legacy = <String, dynamic>{
      'status': 'findingDriver',
      'savedAt': '2026-09-24T10:00:00+02:00',
      'pickupAddress': 'Pickup',
      'destinationAddress': 'Destination',
      'pickupLat': 59.33,
      'pickupLng': 18.06,
      'destinationLat': 59.34,
      'destinationLng': 18.07,
      'rideType': 'Movera',
      'price': 100,
      'paymentMethod': 'Apple Pay',
      'rideId': 'legacy-1',
    };
    final restored = RideSnapshot.fromJson(legacy);
    expect(restored, isNotNull);
    expect(restored!.savedAt, DateTime.utc(2026, 9, 24, 8));
    expect(restored.createdAt, restored.savedAt);
    expect(restored.toJson()['schemaVersion'], RideSnapshot.currentSchemaVersion);
  });

  test('malformed and future snapshot schemas are rejected', () {
    expect(RideSnapshot.fromJson(<String, dynamic>{'status': 'findingDriver'}), isNull);
    final future = _snapshot('future').toJson()
      ..['schemaVersion'] = RideSnapshot.currentSchemaVersion + 1;
    expect(RideSnapshot.fromJson(future), isNull);
  });

  test('corrupt stored snapshot does not manufacture a ride', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      RideSnapshotStore.key: jsonEncode(<String, dynamic>{
        'schemaVersion': RideSnapshot.currentSchemaVersion,
        'status': 'findingDriver',
        'savedAt': 'not-a-date',
      }),
    });
    expect(await RideSnapshotStore.read(), isNull);
    expect(await RideSnapshotStore.readForArchive(), isNull);
  });

  test('concurrent history archives retain every ride exactly once', () async {
    final created = DateTime.utc(2026, 9, 24, 9);
    await Future.wait(<Future<void>>[
      OnDemandRideHistoryStore.archive(
        _snapshot('a', createdAt: created),
        terminalStatus: RideStatus.tripCompleted,
        endedAt: DateTime.utc(2026, 9, 24, 10),
      ),
      OnDemandRideHistoryStore.archive(
        _snapshot('b', createdAt: created.add(const Duration(minutes: 1))),
        terminalStatus: RideStatus.cancelledByRider,
        endedAt: DateTime.utc(2026, 9, 24, 11),
      ),
    ]);
    final history = await OnDemandRideHistoryStore.read();
    expect(history.map((ride) => ride.reservationId).toSet(), {
      'ondemand-a',
      'ondemand-b',
    });
    // rider-36: stored as UTC, read back in the rider's local time.
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(OnDemandRideHistoryStore.key)!);
    expect(
      DateTime.parse((stored as List).first['scheduledPickupAt']).isUtc,
      isTrue,
    );
    expect(history.first.scheduledPickupAt.isUtc, isFalse);
    expect(
      history.first.scheduledPickupAt,
      DateTime.utc(2026, 9, 24, 11).toLocal(),
    );
  });

  test('history preserves original creation time instead of latest save time', () async {
    final created = DateTime.utc(2026, 9, 24, 8);
    final ride = _snapshot('created-at', createdAt: created).copyWith(
      savedAt: DateTime.utc(2026, 9, 24, 12),
    );
    await OnDemandRideHistoryStore.archive(
      ride,
      terminalStatus: RideStatus.tripCompleted,
      endedAt: DateTime.utc(2026, 9, 24, 13),
    );
    final history = await OnDemandRideHistoryStore.read();
    expect(history.single.createdAt, created);
  });
}
