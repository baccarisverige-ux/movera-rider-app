import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/data/local_reservation_repository.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_transition.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot snapshotFor(
  RideStatus status, {
  String rideId = 'pre15-matrix',
  DateTime? savedAt,
}) {
  return RideSnapshot(
    status: status,
    savedAt: savedAt ?? DateTime.now(),
    pickupAddress: 'Stockholm Central Station',
    destinationAddress: 'Arlanda Airport',
    pickupLat: 59.3293,
    pickupLng: 18.0686,
    destinationLat: 59.6519,
    destinationLng: 17.9186,
    rideType: 'Movera',
    price: 349,
    paymentMethod: 'Apple Pay',
    rideId: rideId,
  );
}

List<RideStatus>? pathFromIdleTo(RideStatus target) {
  final queue = <List<RideStatus>>[
    <RideStatus>[RideStatus.idle],
  ];
  final visited = <RideStatus>{RideStatus.idle};

  while (queue.isNotEmpty) {
    final path = queue.removeAt(0);
    final current = path.last;
    if (current == target) return path;

    for (final next in RideStatus.values) {
      if (!canTransition(current, next) || visited.contains(next)) continue;
      visited.add(next);
      queue.add(<RideStatus>[...path, next]);
    }
  }
  return null;
}

RideSession applyPath(List<RideStatus> path, {String rideId = 'pre15-path'}) {
  final session = RideSession(rideId: rideId);
  expect(path.first, RideStatus.idle);
  for (final next in path.skip(1)) {
    session.apply(next);
  }
  return session;
}

Future<void> waitFor(
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


/// rider-u29: books a live ride on the stand-in server (quote, then ride)
/// and answers its server-made id, so the mock's accept is the real one.
/// The mock no longer shows a driver the server refused, as it did for
/// the made-up ride ids these tests used before.
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
  });

  testWidgets(
    'PRE15 lifecycle graph: every canonical status is reachable and terminals stay immutable',
    (tester) async {
      // 27 + the four distinct terminal causes of contract v0.3.0.
      expect(RideStatus.values.length, 31);

      for (final target in RideStatus.values) {
        final path = pathFromIdleTo(target);
        expect(
          path,
          isNotNull,
          reason: 'Every canonical status must be reachable from idle: ${target.name}',
        );
        final session = applyPath(path!, rideId: 'pre15-${target.name}');
        expect(session.status, target);

        if (target.isTerminal) {
          for (final next in RideStatus.values) {
            expect(
              canTransition(target, next),
              isFalse,
              reason: 'Terminal ${target.name} must reject ${next.name}',
            );
          }
        }
      }
    },
  );

  testWidgets(
    'PRE15 success path: Book Now can reach closed through explicit approaching-dropoff',
    (tester) async {
      const path = <RideStatus>[
        RideStatus.idle,
        RideStatus.pickupSelected,
        RideStatus.destinationSelected,
        RideStatus.quoteLoading,
        RideStatus.rideOptionsReady,
        RideStatus.rideSelected,
        RideStatus.paymentSelected,
        RideStatus.bookingRequested,
        RideStatus.findingDriver,
        RideStatus.driverAssigned,
        RideStatus.driverArriving,
        RideStatus.driverWaiting,
        RideStatus.tripStarted,
        RideStatus.tripInProgress,
        RideStatus.approachingDropoff,
        RideStatus.tripCompleted,
        RideStatus.paymentProcessing,
        RideStatus.paymentFinalized,
        RideStatus.ratingPending,
        RideStatus.closed,
      ];

      final session = applyPath(path, rideId: 'pre15-success-approach');
      expect(session.status, RideStatus.closed);
      expect(session.status.isTerminal, isTrue);
    },
  );

  testWidgets(
    'PRE15 success variant: transport may complete directly from in-trip without approach event',
    (tester) async {
      const path = <RideStatus>[
        RideStatus.idle,
        RideStatus.pickupSelected,
        RideStatus.destinationSelected,
        RideStatus.quoteLoading,
        RideStatus.rideOptionsReady,
        RideStatus.rideSelected,
        RideStatus.paymentSelected,
        RideStatus.bookingRequested,
        RideStatus.findingDriver,
        RideStatus.driverAssigned,
        RideStatus.driverArriving,
        RideStatus.driverWaiting,
        RideStatus.tripStarted,
        RideStatus.tripInProgress,
        RideStatus.tripCompleted,
        RideStatus.paymentProcessing,
        RideStatus.paymentFinalized,
        RideStatus.ratingPending,
        RideStatus.closed,
      ];

      final session = applyPath(path, rideId: 'pre15-success-direct');
      expect(session.status, RideStatus.closed);
    },
  );

  testWidgets(
    'PRE15 search branches: delay, retry, no-driver, booking expiry and rider/system cancel all terminate correctly',
    (tester) async {
      final branches = <List<RideStatus>>[
        const [
          RideStatus.idle,
          RideStatus.pickupSelected,
          RideStatus.destinationSelected,
          RideStatus.quoteLoading,
          RideStatus.bookingExpired,
        ],
        const [
          RideStatus.idle,
          RideStatus.pickupSelected,
          RideStatus.destinationSelected,
          RideStatus.quoteLoading,
          RideStatus.rideOptionsReady,
          RideStatus.rideSelected,
          RideStatus.paymentSelected,
          RideStatus.bookingRequested,
          RideStatus.bookingExpired,
        ],
        const [
          RideStatus.idle,
          RideStatus.pickupSelected,
          RideStatus.destinationSelected,
          RideStatus.quoteLoading,
          RideStatus.rideOptionsReady,
          RideStatus.rideSelected,
          RideStatus.paymentSelected,
          RideStatus.bookingRequested,
          RideStatus.cancelledByRider,
        ],
        const [
          RideStatus.idle,
          RideStatus.pickupSelected,
          RideStatus.destinationSelected,
          RideStatus.quoteLoading,
          RideStatus.rideOptionsReady,
          RideStatus.rideSelected,
          RideStatus.paymentSelected,
          RideStatus.bookingRequested,
          RideStatus.cancelledBySystem,
        ],
        const [
          RideStatus.idle,
          RideStatus.pickupSelected,
          RideStatus.destinationSelected,
          RideStatus.quoteLoading,
          RideStatus.rideOptionsReady,
          RideStatus.rideSelected,
          RideStatus.paymentSelected,
          RideStatus.bookingRequested,
          RideStatus.findingDriver,
          RideStatus.searchDelayed,
          RideStatus.noDriverFound,
        ],
        const [
          RideStatus.idle,
          RideStatus.pickupSelected,
          RideStatus.destinationSelected,
          RideStatus.quoteLoading,
          RideStatus.rideOptionsReady,
          RideStatus.rideSelected,
          RideStatus.paymentSelected,
          RideStatus.bookingRequested,
          RideStatus.findingDriver,
          RideStatus.searchDelayed,
          RideStatus.findingDriver,
          RideStatus.driverAssigned,
        ],
      ];

      for (var i = 0; i < branches.length; i += 1) {
        final session = applyPath(branches[i], rideId: 'pre15-search-$i');
        expect(session.status, branches[i].last);
      }
    },
  );

  testWidgets(
    'PRE15 matched branches: rider, driver and system exits are represented at every legal stage',
    (tester) async {
      const common = <RideStatus>[
        RideStatus.idle,
        RideStatus.pickupSelected,
        RideStatus.destinationSelected,
        RideStatus.quoteLoading,
        RideStatus.rideOptionsReady,
        RideStatus.rideSelected,
        RideStatus.paymentSelected,
        RideStatus.bookingRequested,
        RideStatus.findingDriver,
        RideStatus.driverAssigned,
      ];

      final suffixes = <List<RideStatus>>[
        const [RideStatus.cancelledByRider],
        const [RideStatus.cancelledByDriver],
        const [RideStatus.cancelledBySystem],
        const [RideStatus.driverArriving, RideStatus.cancelledByRider],
        const [RideStatus.driverArriving, RideStatus.cancelledByDriver],
        const [
          RideStatus.driverArriving,
          RideStatus.driverWaiting,
          RideStatus.cancelledByRider,
        ],
        const [
          RideStatus.driverArriving,
          RideStatus.driverWaiting,
          RideStatus.cancelledByDriver,
        ],
        const [
          RideStatus.driverArriving,
          RideStatus.driverWaiting,
          RideStatus.tripStarted,
          RideStatus.tripInProgress,
          RideStatus.cancelledBySystem,
        ],
        const [
          RideStatus.driverArriving,
          RideStatus.driverWaiting,
          RideStatus.tripStarted,
          RideStatus.tripInProgress,
          RideStatus.approachingDropoff,
          RideStatus.cancelledBySystem,
        ],
      ];

      for (var i = 0; i < suffixes.length; i += 1) {
        final session = applyPath(
          <RideStatus>[...common, ...suffixes[i]],
          rideId: 'pre15-matched-$i',
        );
        expect(session.status, suffixes[i].last);
        expect(session.status.isTerminal, isTrue);
      }
    },
  );

  testWidgets(
    'PRE15 payment branches: failure before or during payment and successful rating close are all valid',
    (tester) async {
      const toTripComplete = <RideStatus>[
        RideStatus.idle,
        RideStatus.pickupSelected,
        RideStatus.destinationSelected,
        RideStatus.quoteLoading,
        RideStatus.rideOptionsReady,
        RideStatus.rideSelected,
        RideStatus.paymentSelected,
        RideStatus.bookingRequested,
        RideStatus.findingDriver,
        RideStatus.driverAssigned,
        RideStatus.driverArriving,
        RideStatus.driverWaiting,
        RideStatus.tripStarted,
        RideStatus.tripInProgress,
        RideStatus.tripCompleted,
      ];

      final failAtCompletion = applyPath(
        <RideStatus>[...toTripComplete, RideStatus.paymentFailed],
        rideId: 'pre15-payment-fail-complete',
      );
      expect(failAtCompletion.status, RideStatus.paymentFailed);

      final failDuringProcessing = applyPath(
        <RideStatus>[
          ...toTripComplete,
          RideStatus.paymentProcessing,
          RideStatus.paymentFailed,
        ],
        rideId: 'pre15-payment-fail-processing',
      );
      expect(failDuringProcessing.status, RideStatus.paymentFailed);

      final success = applyPath(
        <RideStatus>[
          ...toTripComplete,
          RideStatus.paymentProcessing,
          RideStatus.paymentFinalized,
          RideStatus.ratingPending,
          RideStatus.closed,
        ],
        rideId: 'pre15-payment-success',
      );
      expect(success.status, RideStatus.closed);
    },
  );

  testWidgets(
    'PRE15 restore matrix: every fresh/stale/terminal state resolves to the correct root surface',
    (tester) async {
      const finding = <RideStatus>{
        RideStatus.bookingRequested,
        RideStatus.findingDriver,
        RideStatus.searchDelayed,
      };
      const waiting = <RideStatus>{
        RideStatus.driverAssigned,
        RideStatus.driverArriving,
        RideStatus.driverWaiting,
        RideStatus.tripStarted,
        RideStatus.tripInProgress,
        RideStatus.approachingDropoff,
      };
      const complete = <RideStatus>{
        RideStatus.tripCompleted,
        RideStatus.paymentProcessing,
        RideStatus.paymentFinalized,
        RideStatus.ratingPending,
      };

      final coordinator = RideRestoreCoordinator(reader: () async => null);
      final staleAt = DateTime.now().subtract(const Duration(days: 1));

      for (final status in RideStatus.values) {
        final expected = status.isTerminal
            ? RestoredSurface.home
            : finding.contains(status)
                ? RestoredSurface.finding
                : waiting.contains(status)
                    ? RestoredSurface.waiting
                    : complete.contains(status)
                        ? RestoredSurface.complete
                        : RestoredSurface.home;

        expect(
          coordinator.surfaceFor(snapshotFor(status)),
          expected,
          reason: 'Fresh ${status.name} restored to wrong surface',
        );
        expect(
          coordinator.surfaceFor(snapshotFor(status, savedAt: staleAt)),
          RestoredSurface.home,
          reason: 'Stale ${status.name} must restore Home',
        );
      }
    },
  );

  testWidgets(
    'PRE15 realtime: driver cancel re-search retains ride identity and assigns another driver',
    (tester) async {
      final realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
      );
      addTearDown(realtime.dispose);

      const rideId = 'pre15-driver-research';
      final events = <RideStatus>[];
      final sub = realtime.subscribe(rideId).listen(
        (event) => events.add(event.status),
      );
      addTearDown(sub.cancel);

      realtime.assignNow();
      await waitFor(
        () => realtime.lastStatus == RideStatus.driverAssigned,
        label: 'first driver assignment',
      );
      final firstDriver = realtime.lastDriver?.id;
      expect(firstDriver, isNotNull);

      realtime.cancelByDriver();
      expect(realtime.lastStatus, RideStatus.cancelledByDriver);
      realtime.researchAfterDriverCancel();
      expect(realtime.lastStatus, RideStatus.findingDriver);

      realtime.assignNow();
      await waitFor(
        () => realtime.lastStatus == RideStatus.driverAssigned,
        label: 'replacement driver assignment',
      );
      final replacement = realtime.lastDriver?.id;

      expect(replacement, isNotNull);
      expect(replacement, isNot(firstDriver));
      expect(events, contains(RideStatus.cancelledByDriver));
      expect(
        events.where((event) => event == RideStatus.driverAssigned).length,
        greaterThanOrEqualTo(2),
      );
    },
  );

  testWidgets(
    'PRE15 realtime: rider cancel prevents late assignment resurrection',
    (tester) async {
      final realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
      );
      addTearDown(realtime.dispose);

      realtime.subscribe('pre15-rider-cancel').listen((_) {});
      realtime.cancelRide();
      expect(realtime.lastStatus, RideStatus.cancelledByRider);

      realtime.assignNow();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(realtime.lastStatus, RideStatus.cancelledByRider);
      expect(realtime.lastDriver, isNull);
    },
  );

  testWidgets(
    'PRE15 realtime: disconnect/reconnect keeps the authoritative active status',
    (tester) async {
      final api = ApiClient(client: InProcessMockClient());
      final connection = RealtimeConnection();
      final realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        connection: connection,
        api: api,
      );
      addTearDown(realtime.dispose);

      final rideId = await _bookOnServer(api);
      realtime.subscribe(rideId).listen((_) {});
      realtime.assignNow();
      await waitFor(
        () => realtime.lastStatus == RideStatus.driverAssigned,
        label: 'driver assignment before reconnect',
      );

      connection.markDisconnected();
      expect(connection.state, RealtimeState.disconnected);
      await realtime.reconnectAndResync(rideId);

      expect(connection.state, RealtimeState.connected);
      expect(realtime.lastStatus, RideStatus.driverAssigned);
    },
  );

  testWidgets(
    'PRE15 scheduled ride: create/edit/assign/en-route/arrive/in-progress/complete keeps one reservation id',
    (tester) async {
      final now = DateTime(2026, 9, 23, 6, 53);
      final controller = ReservationController(
        store: LocalReservationRepository(
          storage: MemoryReservationStorage(),
          nextId: () => 'pre15-rsv-main',
          clock: () => now,
        ),
      );

      final created = await controller.create(
        ReservationDraft(
          scheduledPickupAt: now.add(const Duration(minutes: 2)),
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

      final edited = await controller.update(
        created.reservationId,
        const ReservationPatch(
          paymentMethod: 'Google Pay',
          note: 'Front entrance',
        ),
      );
      expect(edited.reservationId, created.reservationId);
      expect(edited.paymentMethod, 'Google Pay');

      await controller.startLiveIfDue(now: now);
      expect(
        controller.byId(created.reservationId)?.status,
        ReservationStatus.driverAssignmentPending,
      );

      const driver = ReservationDriver(
        firstName: 'Amina',
        rating: 4.9,
        vehicle: 'Volvo EX40',
        plate: 'ABC 123',
      );
      final assigned = await controller.assignMockDriver(
        created.reservationId,
        driver: driver,
      );
      expect(assigned.reservationId, created.reservationId);
      expect(assigned.status, ReservationStatus.driverAssigned);

      await controller.startLiveIfDue(now: now);
      expect(
        controller.byId(created.reservationId)?.status,
        ReservationStatus.driverEnRoute,
      );

      final arrived = await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.driverArrived),
      );
      expect(arrived.reservationId, created.reservationId);

      final inProgress = await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.inProgress),
      );
      expect(inProgress.reservationId, created.reservationId);
      expect(inProgress.status, ReservationStatus.inProgress);

      final completed = await controller.update(
        created.reservationId,
        const ReservationPatch(status: ReservationStatus.completed),
      );
      expect(completed.reservationId, created.reservationId);
      expect(completed.status, ReservationStatus.completed);
      expect(controller.completed().single.reservationId, created.reservationId);
    },
  );

  testWidgets(
    'PRE15 scheduled ride: driver cancel reassigns same reservation, rider cancel ends it, return ride gets a linked new id',
    (tester) async {
      var ids = 0;
      final now = DateTime(2026, 9, 23, 9);
      final controller = ReservationController(
        store: LocalReservationRepository(
          storage: MemoryReservationStorage(),
          nextId: () => 'pre15-rsv-${++ids}',
          clock: () => now,
        ),
      );

      final original = await controller.create(
        ReservationDraft(
          scheduledPickupAt: now.add(const Duration(hours: 2)),
          pickup: const ReservationPlace(label: 'Södertälje'),
          destination: const ReservationPlace(label: 'Stockholm'),
          categoryId: 'comfort',
          categoryName: 'Comfort',
          categoryImage: 'assets/images/rides/comfort.webp',
          price: 399,
          paymentMethod: 'Apple Pay',
        ),
      );

      const driver = ReservationDriver(
        firstName: 'Nora',
        rating: 4.8,
        vehicle: 'Mercedes EQE',
        plate: 'XYZ 789',
      );
      await controller.assignMockDriver(original.reservationId, driver: driver);
      final reassignment = await controller.driverCancelled(
        original.reservationId,
      );
      expect(reassignment.reservationId, original.reservationId);
      expect(reassignment.status, ReservationStatus.driverAssignmentPending);
      expect(reassignment.driver, isNull);

      final cancelled = await controller.cancel(
        original.reservationId,
        reason: 'plans_changed',
      );
      expect(cancelled.reservationId, original.reservationId);
      expect(cancelled.status, ReservationStatus.cancelled);

      final returnRide = await controller.planReturn(
        cancelled,
        scheduledPickupAt: now.add(const Duration(days: 1)),
      );
      expect(returnRide.reservationId, isNot(original.reservationId));
      expect(returnRide.parentReservationId, original.reservationId);
      expect(returnRide.pickup.label, original.destination.label);
      expect(returnRide.destination.label, original.pickup.label);
    },
  );
}
