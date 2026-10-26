import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/application/push_coordinator.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';

class _FakePushService implements PushService {
  final StreamController<PushPayload> foreground =
      StreamController<PushPayload>.broadcast();
  final StreamController<PushPayload> opened =
      StreamController<PushPayload>.broadcast();

  PushPayload? initial;

  @override
  Stream<PushPayload> get foregroundMessages => foreground.stream;

  @override
  Stream<PushPayload> get openedMessages => opened.stream;

  @override
  Future<PushPayload?> takeInitialMessage() async {
    final value = initial;
    initial = null;
    return value;
  }

  @override
  Future<void> register() async {}

  @override
  Future<void> unregister() async {}

  Future<void> dispose() async {
    await foreground.close();
    await opened.close();
  }
}

void main() {
  test('push payload only routes allowlisted ride events to rides', () {
    final direct = PushPayload.fromMap({
      'type': 'ride.driver_assigned',
      'rideId': 'ride-1',
      'deepLink': 'movera://notifications',
    });
    expect(direct.destination, PushDestination.ride);
    expect(direct.routedRideId, 'ride-1');

    final deepLink = PushPayload.fromMap({
      'type': 'trip.updated',
      'deepLink': 'movera://ride/ride-2',
    });
    expect(deepLink.destination, PushDestination.ride);
    expect(deepLink.routedRideId, 'ride-2');

    final untrusted = PushPayload.fromMap({
      'type': 'account.updated',
      'deepLink': 'movera://ride/ride-3',
    });
    expect(untrusted.destination, PushDestination.notifications);
    expect(untrusted.routedRideId, isNull);

    final arbitrary = PushPayload.fromMap({
      'type': 'ride.updated',
      'deepLink': 'https://example.com/admin',
    });
    expect(arbitrary.destination, PushDestination.notifications);
  });

  test('missing push type is rejected rather than guessed', () {
    expect(
      () => PushPayload.fromMap({'rideId': 'ride-1'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('foreground push updates feed without navigating', () async {
    final push = _FakePushService();
    addTearDown(push.dispose);
    final store = NotificationsRepository(
      now: () => DateTime(2026, 9, 26, 20, 45),
    );
    var rideOpens = 0;
    var notificationOpens = 0;
    final coordinator = PushCoordinator(
      push: push,
      notifications: NotificationsController(store: store),
      openRide: (_) async {
        rideOpens += 1;
        return true;
      },
      openNotifications: () => notificationOpens += 1,
    );
    addTearDown(coordinator.stop);
    await coordinator.start();

    push.foreground.add(
      const PushPayload(
        type: 'account.updated',
        title: 'Account updated',
        body: 'Your security settings changed.',
        messageId: 'message-1',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(rideOpens, 0);
    expect(notificationOpens, 0);
    expect(store.all(), hasLength(1));
    expect(store.all().single.read, isFalse);
    expect(store.all().single.messageId, 'message-1');
  });

  test(
    'opened ride push resync route is requested and marks feed read',
    () async {
      final push = _FakePushService();
      addTearDown(push.dispose);
      final store = NotificationsRepository();
      final openedRideIds = <String>[];
      var notificationOpens = 0;
      final coordinator = PushCoordinator(
        push: push,
        notifications: NotificationsController(store: store),
        openRide: (rideId) async {
          openedRideIds.add(rideId);
          return true;
        },
        openNotifications: () => notificationOpens += 1,
      );
      addTearDown(coordinator.stop);
      await coordinator.start();

      push.opened.add(
        const PushPayload(
          type: 'ride.driver_assigned',
          rideId: 'ride-authoritative',
          title: 'Driver assigned',
          body: 'Your driver is on the way.',
          messageId: 'message-2',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(openedRideIds, ['ride-authoritative']);
      expect(notificationOpens, 0);
      expect(store.all(), hasLength(1));
      expect(store.all().single.read, isTrue);
    },
  );

  test('cold-start non-ride push opens Notifications once', () async {
    final push = _FakePushService()
      ..initial = const PushPayload(
        type: 'payment.receipt_ready',
        title: 'Receipt ready',
        body: 'Your ride receipt is available.',
        messageId: 'message-3',
      );
    addTearDown(push.dispose);
    final store = NotificationsRepository();
    var notificationOpens = 0;
    final coordinator = PushCoordinator(
      push: push,
      notifications: NotificationsController(store: store),
      openRide: (_) async => false,
      openNotifications: () => notificationOpens += 1,
    );
    addTearDown(coordinator.stop);

    await coordinator.start();
    await coordinator.start();

    expect(notificationOpens, 1);
    expect(store.all(), hasLength(1));
    expect(store.all().single.read, isTrue);
  });

  test(
    'foreground then opened same message deduplicates and becomes read',
    () async {
      final push = _FakePushService();
      addTearDown(push.dispose);
      final store = NotificationsRepository();
      final coordinator = PushCoordinator(
        push: push,
        notifications: NotificationsController(store: store),
        openRide: (_) async => false,
        openNotifications: () {},
      );
      addTearDown(coordinator.stop);
      await coordinator.start();

      const payload = PushPayload(
        type: 'account.updated',
        title: 'Security update',
        body: 'Review your account.',
        messageId: 'same-message',
      );
      push.foreground.add(payload);
      await Future<void>.delayed(Duration.zero);
      expect(store.all().single.read, isFalse);

      push.opened.add(payload);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(store.all(), hasLength(1));
      expect(store.all().single.read, isTrue);
    },
  );

  test('data-only ride push never fabricates notification copy', () async {
    final push = _FakePushService();
    addTearDown(push.dispose);
    final store = NotificationsRepository();
    final coordinator = PushCoordinator(
      push: push,
      notifications: NotificationsController(store: store),
      openRide: (_) async => true,
      openNotifications: () {},
    );
    addTearDown(coordinator.stop);
    await coordinator.start();

    push.foreground.add(
      const PushPayload(
        type: 'ride.updated',
        rideId: 'ride-data-only',
        messageId: 'message-4',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(store.all(), isEmpty);
  });
}
