import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/payments/api_payment_gateway.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/finding_driver_repository.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot _snapshot(String id, RideStatus status) => RideSnapshot(
  status: status,
  savedAt: DateTime.now(),
  pickupAddress: 'Stockholm Central',
  destinationAddress: 'Arlanda Airport',
  pickupLat: 59.3293,
  pickupLng: 18.0686,
  destinationLat: 59.6519,
  destinationLng: 17.9186,
  rideType: 'Movera',
  price: 349,
  paymentMethod: 'Apple Pay',
  rideId: id,
);

/// Books a live ride on the stand-in server (quote, then ride) and answers
/// its server-made id.
Future<String> _bookOnServer(ApiClient api) async {
  final quoted = await api.post(
    '/api/v1/quotes',
    body: <String, dynamic>{
      'rideType': 'economy',
      'pickup': <String, dynamic>{'lat': 59.3293, 'lng': 18.0686},
      'destination': <String, dynamic>{'lat': 59.6519, 'lng': 17.9186},
    },
  );
  final quote = Map<String, dynamic>.from(quoted['quote'] as Map);
  final created = await api.post(
    '/api/v1/rides',
    body: <String, dynamic>{
      'categoryId': 'economy',
      'paymentMethod': 'apple_pay',
      'pickupAddress': 'Stockholm Central',
      'destinationAddress': 'Arlanda Airport',
      'pickupLat': 59.3293,
      'pickupLng': 18.0686,
      'destinationLat': 59.6519,
      'destinationLng': 17.9186,
      'quoteId': quote['id'],
      'quoteSignedPayload': quote['signedPayload'],
      'quoteExpiresAt': quote['expiresAt'],
      'quoteTotalMinor': quote['totalMinor'],
      'fare': <String, dynamic>{
        'amountMinor': quote['totalMinor'],
        'currency': quote['currency'],
      },
    },
  );
  return (created['ride'] as Map)['id'] as String;
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
  String label = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $label');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
  });

  test(
    'Phase 85 background/kill/resume matrix restores every active ride stage',
    () async {
      const expected = <RideStatus, RestoredSurface>{
        RideStatus.bookingRequested: RestoredSurface.finding,
        RideStatus.findingDriver: RestoredSurface.finding,
        RideStatus.searchDelayed: RestoredSurface.finding,
        RideStatus.driverAssigned: RestoredSurface.waiting,
        RideStatus.driverArriving: RestoredSurface.waiting,
        RideStatus.driverWaiting: RestoredSurface.waiting,
        RideStatus.tripStarted: RestoredSurface.waiting,
        RideStatus.tripInProgress: RestoredSurface.waiting,
        RideStatus.approachingDropoff: RestoredSurface.waiting,
        RideStatus.tripCompleted: RestoredSurface.complete,
        RideStatus.paymentProcessing: RestoredSurface.complete,
        RideStatus.paymentFinalized: RestoredSurface.complete,
        RideStatus.ratingPending: RestoredSurface.complete,
      };

      var index = 0;
      for (final entry in expected.entries) {
        final id = 'phase85-resume-${index++}';
        await RideSnapshotStore.clear();
        await RideSnapshotStore.save(_snapshot(id, entry.key));

        // New coordinator object + storage read models a fresh app process.
        final restarted = RideRestoreCoordinator(
          reader: RideSnapshotStore.read,
          resync: (_) async {},
        );
        final persisted = await RideSnapshotStore.read();

        expect(persisted?.rideId, id);
        expect(persisted?.status, entry.key);
        expect(
          restarted.surfaceFor(persisted),
          entry.value,
          reason: '${entry.key.name} restored to the wrong root surface',
        );

        // Background/pagehide touches freshness but must not change identity
        // or lifecycle state.
        restarted.onPageHide();
        await Future<void>.delayed(Duration.zero);
        final touched = await RideSnapshotStore.read();
        expect(touched?.rideId, id);
        expect(touched?.status, entry.key);
      }
    },
  );

  test(
    'Phase 85 driver cancellation replacement keeps one ride identity',
    () async {
      final api = ApiClient(client: InProcessMockClient());
      final realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        api: api,
      );
      addTearDown(realtime.dispose);

      // rider-u29: the ride is booked on the stand-in server first, so the
      // accept is the real one (the mock no longer shows a driver the server
      // refused, as it did for a ride id the server never had).
      final rideId = await _bookOnServer(api);
      realtime.subscribe(rideId).listen((_) {});
      realtime.assignNow();
      await _waitFor(
        () => realtime.lastStatus == RideStatus.driverAssigned,
        label: 'first assignment',
      );
      final firstDriver = realtime.lastDriver;
      expect(firstDriver, isNotNull);

      realtime.cancelByDriver();
      expect(realtime.lastStatus, RideStatus.cancelledByDriver);

      realtime.researchAfterDriverCancel();
      expect(realtime.lastStatus, RideStatus.findingDriver);
      realtime.assignNow();
      await _waitFor(
        () =>
            realtime.lastStatus == RideStatus.driverAssigned &&
            realtime.lastDriver?.id != firstDriver!.id,
        label: 'replacement assignment',
      );

      expect(realtime.lastDriver, isNotNull);
      expect(realtime.lastDriver!.id, isNot(firstDriver!.id));
    },
  );

  test(
    'Phase 85 rider cancellation is terminal before and after match',
    () async {
      final before = MockRideRealtime(assignAfter: const Duration(days: 1));
      before.subscribe('phase85-cancel-before').listen((_) {});
      before.cancelRide();
      before.assignNow();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(before.lastStatus, RideStatus.cancelledByRider);
      expect(before.lastDriver, isNull);
      before.dispose();

      final after = MockRideRealtime(assignAfter: const Duration(days: 1));
      after.subscribe('phase85-cancel-after').listen((_) {});
      after.assignNow();
      await _waitFor(
        () => after.lastStatus == RideStatus.driverAssigned,
        label: 'assignment before rider cancellation',
      );
      expect(after.lastDriver, isNotNull);

      after.cancelRide();
      after.assignNow();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(after.lastStatus, RideStatus.cancelledByRider);
      after.dispose();
    },
  );

  test(
    'Phase 85 payment failure can retry the same real payment intent',
    () async {
      final backend = InProcessMockClient();
      final gateway = ApiPaymentGateway(api: ApiClient(client: backend));

      final intent = await gateway.create(
        amountMinor: 34900,
        currency: 'SEK',
        idempotencyKey: 'phase85-payment-create',
      );
      expect(await gateway.status(intent.id), 'requires_confirmation');

      backend.failNext = true;
      await expectLater(gateway.confirm(intent.id), throwsA(isA<Exception>()));
      expect(await gateway.status(intent.id), 'requires_confirmation');

      expect(await gateway.confirm(intent.id), 'succeeded');
      expect(await gateway.status(intent.id), 'succeeded');
    },
  );

  test(
    'Phase 85 no-driver branch clears the live search and restores Home',
    () async {
      const rideId = 'phase85-no-driver';
      final snapshot = _snapshot(rideId, RideStatus.findingDriver);
      await RideSnapshotStore.save(snapshot);

      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      final ride = RideSession(rideId: rideId);
      final controller = FindingDriverController(
        store: FindingDriverRepository(),
        realtime: realtime,
        ride: ride,
        api: ApiClient(client: InProcessMockClient()),
      );
      controller.start(snapshot: snapshot, onTick: (_) {}, onMatched: () {});

      realtime.emit(RideStatus.noDriverFound, sequence: 5);
      await _waitFor(
        () => ride.status == RideStatus.noDriverFound,
        label: 'no-driver terminal event',
      );
      await _waitFor(
        () => controller.ownedRideId == rideId,
        label: 'terminal owner identity',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final restarted = RideRestoreCoordinator(reader: RideSnapshotStore.read);
      final persisted = await RideSnapshotStore.read();
      expect(persisted, isNull);
      expect(restarted.surfaceFor(persisted), RestoredSurface.home);

      controller.dispose();
      realtime.dispose();
    },
  );

  test(
    'Phase 85 scheduled ride persists, assigns, drops driver and reassigns same id',
    () async {
      final now = DateTime(2026, 9, 27, 8);
      final controller = ReservationController(
        store: LocalReservationRepository(
          storage: MemoryReservationStorage(),
          nextId: () => 'phase85-reservation',
          clock: () => now,
        ),
        clock: () => now,
      );

      final created = await controller.create(
        ReservationDraft(
          scheduledPickupAt: now.add(const Duration(minutes: 1)),
          pickup: const ReservationPlace(label: 'Home'),
          destination: const ReservationPlace(label: 'Arlanda Airport'),
          categoryId: 'economy',
          categoryName: 'Movera',
          categoryImage: 'assets/images/rides/movera.webp',
          price: 349,
          paymentMethod: 'Apple Pay',
        ),
      );
      expect(created.status, ReservationStatus.scheduled);

      await controller.startLiveIfDue(now: now);
      expect(
        controller.byId(created.reservationId)?.status,
        ReservationStatus.driverAssignmentPending,
      );

      const first = ReservationDriver(
        firstName: 'Amina',
        vehicle: 'Volvo EX40',
        plate: 'ABC 123',
      );
      final assigned = await controller.applyDriverAssignment(
        created.reservationId,
        driver: first,
      );
      expect(assigned.reservationId, created.reservationId);
      expect(assigned.driver?.firstName, 'Amina');

      final dropped = await controller.applyDriverCancellation(
        created.reservationId,
      );
      expect(dropped.reservationId, created.reservationId);
      expect(dropped.status, ReservationStatus.driverAssignmentPending);
      expect(dropped.driver, isNull);

      const second = ReservationDriver(
        firstName: 'Nora',
        vehicle: 'Mercedes EQE',
        plate: 'XYZ 789',
      );
      final reassigned = await controller.applyDriverAssignment(
        created.reservationId,
        driver: second,
      );
      expect(reassigned.reservationId, created.reservationId);
      expect(reassigned.driver?.firstName, 'Nora');
    },
  );

  test(
    'Phase 85 offline reconnect resyncs the authoritative active ride',
    () async {
      final backend = InProcessMockClient();
      const rideId = 'phase85-offline-reconnect';
      backend.rides[rideId] = {
        'id': rideId,
        'status': 'driverAssigned',
        'version': 7,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
      final connection = RealtimeConnection();
      final realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        connection: connection,
        api: ApiClient(client: backend),
      );
      addTearDown(realtime.dispose);

      realtime.subscribe(rideId).listen((_) {});
      realtime.assignNow();
      await _waitFor(
        () => realtime.lastStatus == RideStatus.driverAssigned,
        label: 'assigned before disconnect',
      );

      connection.markDisconnected();
      expect(connection.state, RealtimeState.disconnected);

      await realtime.reconnectAndResync(rideId);
      expect(connection.state, RealtimeState.connected);
      expect(realtime.lastStatus, RideStatus.driverAssigned);
    },
  );
}
