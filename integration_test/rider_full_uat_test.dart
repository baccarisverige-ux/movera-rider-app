import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/realtime_connection.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

RideSnapshot _snapshot(
  RideStatus status, {
  required String rideId,
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

Future<void> _waitForStatus(
  MockRideRealtime realtime,
  RideStatus expected, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (realtime.lastStatus == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for ${expected.name}; '
    'last status was ${realtime.lastStatus.name}',
  );
}

Future<void> _waitForSeen(
  List<RideStatus> seen,
  RideStatus expected, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (seen.contains(expected)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(
    'Timed out waiting for observed ${expected.name}; '
    'seen: ${seen.map((status) => status.name).join(', ')}',
  );
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RideSnapshotStore.epoch = 0;
    SafetyController.resetShared();
  });

  testWidgets(
    'Phase 13 UAT: ride lifecycle reaches ratingPending in canonical order',
    (tester) async {
      final api = ApiClient(client: InProcessMockClient());
      final connection = RealtimeConnection();
      final realtime = MockRideRealtime(
        assignAfter: const Duration(days: 1),
        boardAfter: const Duration(milliseconds: 20),
        tripTick: const Duration(milliseconds: 20),
        tripTicks: 2,
        paymentProcessingAfter: const Duration(milliseconds: 20),
        paymentFinalizedAfter: const Duration(milliseconds: 20),
        ratingPendingAfter: const Duration(milliseconds: 20),
        connection: connection,
        api: api,
      );
      addTearDown(realtime.dispose);

      final rideId = await _bookOnServer(api);
      final seen = <RideStatus>[];
      final stream = realtime.subscribe(rideId);
      final sub = stream.listen((event) => seen.add(event.status));
      addTearDown(sub.cancel);

      // subscribe() establishes Finding synchronously before a broadcast
      // listener exists, so record the authoritative current state explicitly.
      seen.add(realtime.lastStatus);

      realtime.assignNow();
      await _waitForStatus(realtime, RideStatus.driverAssigned);
      realtime.markArrivedForTest();
      await _waitForStatus(realtime, RideStatus.ratingPending);
      // lastStatus is updated just before the broadcast stream delivers the
      // same event. Wait for the observer too, because this UAT certifies the
      // externally observed lifecycle order rather than an internal field.
      await _waitForSeen(seen, RideStatus.ratingPending);

      for (final expected in const [
        RideStatus.findingDriver,
        RideStatus.driverAssigned,
        RideStatus.driverWaiting,
        RideStatus.tripStarted,
        RideStatus.tripInProgress,
        RideStatus.tripCompleted,
        RideStatus.paymentProcessing,
        RideStatus.paymentFinalized,
        RideStatus.ratingPending,
      ]) {
        expect(
          seen,
          contains(expected),
          reason: 'full lifecycle must include ${expected.name}',
        );
      }

      int at(RideStatus status) => seen.indexOf(status);
      expect(
        at(RideStatus.driverAssigned),
        greaterThan(at(RideStatus.findingDriver)),
      );
      expect(
        at(RideStatus.driverWaiting),
        greaterThan(at(RideStatus.driverAssigned)),
      );
      expect(
        at(RideStatus.tripStarted),
        greaterThan(at(RideStatus.driverWaiting)),
      );
      expect(
        at(RideStatus.tripInProgress),
        greaterThan(at(RideStatus.tripStarted)),
      );
      expect(
        at(RideStatus.tripCompleted),
        greaterThan(at(RideStatus.tripInProgress)),
      );
      expect(
        at(RideStatus.paymentProcessing),
        greaterThan(at(RideStatus.tripCompleted)),
      );
      expect(
        at(RideStatus.paymentFinalized),
        greaterThan(at(RideStatus.paymentProcessing)),
      );
      expect(
        at(RideStatus.ratingPending),
        greaterThan(at(RideStatus.paymentFinalized)),
      );
      expect(connection.state, RealtimeState.connected);
    },
  );

  testWidgets(
    'Phase 13 UAT: driver cancel re-search keeps ride and changes driver',
    (tester) async {
      final realtime = MockRideRealtime(assignAfter: const Duration(days: 1));
      addTearDown(realtime.dispose);

      const rideId = 'uat-driver-research';
      final seen = <RideStatus>[];
      final sub = realtime
          .subscribe(rideId)
          .listen((event) => seen.add(event.status));
      addTearDown(sub.cancel);

      realtime.assignNow();
      await _waitForStatus(realtime, RideStatus.driverAssigned);
      final firstDriver = realtime.lastDriver?.id;
      expect(firstDriver, isNotNull);

      realtime.cancelByDriver();
      expect(realtime.lastStatus, RideStatus.cancelledByDriver);

      realtime.researchAfterDriverCancel();
      expect(realtime.lastStatus, RideStatus.findingDriver);

      realtime.assignNow();
      await _waitForStatus(realtime, RideStatus.driverAssigned);
      final secondDriver = realtime.lastDriver?.id;

      expect(secondDriver, isNotNull);
      expect(secondDriver, isNot(firstDriver));
      expect(seen, contains(RideStatus.cancelledByDriver));
      expect(seen, contains(RideStatus.findingDriver));
      expect(
        seen.where((status) => status == RideStatus.driverAssigned).length,
        greaterThanOrEqualTo(2),
      );
    },
  );

  testWidgets(
    'Phase 13 UAT: every external terminal state restores Home and stays terminal',
    (tester) async {
      const terminals = [
        RideStatus.cancelledBySystem,
        RideStatus.noDriverFound,
        RideStatus.paymentFailed,
        RideStatus.bookingExpired,
      ];

      for (final status in terminals) {
        final rideId = 'uat-terminal-${status.name}';
        final session = RideSession(rideId: rideId);
        session.restoreFromBackend(status, id: rideId);
        expect(session.status, status);
        expect(session.status.isTerminal, isTrue);
        expect(session.suppressRestore, isTrue);

        final coordinator = RideRestoreCoordinator(reader: () async => null);
        expect(
          coordinator.surfaceFor(_snapshot(status, rideId: rideId)),
          RestoredSurface.home,
          reason: '${status.name} must never restore an active ride surface',
        );
      }
    },
  );

  testWidgets(
    'Phase 13 UAT: reconnect/resync recovers the shared transport connection',
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
      final sub = realtime.subscribe(rideId).listen((_) {});
      addTearDown(sub.cancel);
      realtime.assignNow();
      await _waitForStatus(realtime, RideStatus.driverAssigned);

      final states = <RealtimeState>[];
      final stateSub = connection.states.listen(states.add);
      addTearDown(stateSub.cancel);

      connection.markDisconnected();
      expect(connection.state, RealtimeState.disconnected);

      await realtime.reconnectAndResync(rideId);

      expect(states, contains(RealtimeState.disconnected));
      expect(states, contains(RealtimeState.reconnecting));
      expect(states, contains(RealtimeState.connected));
      expect(connection.state, RealtimeState.connected);
      expect(realtime.lastStatus, RideStatus.driverAssigned);
    },
  );

  testWidgets(
    'Phase 13 UAT: ride-scoped messages fail closed without send transport and keep inbound truth',
    (tester) async {
      const rideId = 'uat-messages';
      final now = DateTime(2026, 9, 22, 16, 0);
      final controller = MessagesController.forRide(rideId, now: () => now);

      expect(controller.canSendMessages, isFalse);
      expect(controller.send('I am at the pickup'), isFalse);
      expect(controller.messages, isEmpty);

      controller.receive(
        ChatMessage(
          text: 'I can see you',
          sender: ChatMessageSender.driver,
          sentAt: now.add(const Duration(seconds: 1)),
        ),
      );
      controller.receive(
        ChatMessage(
          text: 'Your driver has arrived',
          sender: ChatMessageSender.system,
          kind: ChatMessageKind.systemEvent,
          sentAt: now.add(const Duration(seconds: 2)),
        ),
      );

      expect(controller.messages, hasLength(2));
      expect(controller.messages.first.sender, ChatMessageSender.driver);
      expect(controller.messages.last.isSystem, isTrue);
      expect(controller.unreadCount, 2);

      final reopened = MessagesController.forRide(
        rideId,
        now: () => now.add(const Duration(seconds: 3)),
      );
      expect(reopened.messages, hasLength(2));
      expect(reopened.unreadCount, 2);

      reopened.markAllRead();
      expect(reopened.unreadCount, 0);
    },
  );

  testWidgets(
    'Phase 13 UAT: Safety state changes use the real controller/store contract',
    (tester) async {
      final api = ApiClient(client: InProcessMockClient());
      final safetyStore = SafetyStore(
        local: PreferencesSafetyLocalDataSource(memoryOnly: true),
        remote: ApiSafetyRemoteDataSource(api),
      );
      final safety = SafetyController(session: safetyStore);
      addTearDown(safety.dispose);

      await safety.load();
      await safety.setPinRequired(true);
      expect(safety.preferences.pinRequired, isTrue);

      await safety.addContact(
        name: 'UAT Contact',
        phone: '0701234567',
        relationship: 'Friend',
        shareTrips: true,
      );
      expect(safety.contacts, hasLength(1));

      await safety.setTripShare(
        enabled: true,
        mode: TripShareMode.manual,
        contactIds: [safety.contacts.single.id],
      );
      expect(safety.preferences.tripShareEnabled, isTrue);
      expect(
        safety.preferences.tripShareContactIds,
        contains(safety.contacts.single.id),
      );

      await safety.setRideCheck(true);
      expect(safety.rideCheckPolicy.enabled, isTrue);

      // ARCH-22: the rider shows the PIN; verifying it is the driver app's
      // call, so the rider client has none.
      expect(RegExp(r'^\d{4}$').hasMatch(safety.pin.pin), isTrue);
    },
  );
}
