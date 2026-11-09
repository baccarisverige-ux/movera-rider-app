import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/application/push_coordinator.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';

class _FakePushService implements PushService {
  final StreamController<PushPayload> opened =
      StreamController<PushPayload>.broadcast();

  @override
  Stream<PushPayload> get foregroundMessages => const Stream.empty();

  @override
  Stream<PushPayload> get openedMessages => opened.stream;

  @override
  Future<PushPayload?> takeInitialMessage() async => null;

  @override
  Future<void> register() async {}

  @override
  Future<void> unregister() async {}
}

/// Contract v0.18.53 §75 (support.answerPush): an admin's answer to a
/// ticket is pushed as kind support_reply with the deep link
/// movera://support/{ticketId}; a tap opens that ticket.
void main() {
  test('a support_reply push names its ticket from the deep link', () {
    final push = PushPayload.fromMap({
      'kind': 'support_reply',
      'deepLink': 'movera://support/tck_42',
      'ticketId': 'tck_42',
    });
    expect(push.routedTicketId, 'tck_42');
    expect(push.destination, PushDestination.support);
    expect(push.routedRideId, isNull);

    final riderScheme = PushPayload.fromMap({
      'kind': 'support_reply',
      'deepLink': 'movera-rider://support/tck_43',
    });
    expect(riderScheme.routedTicketId, 'tck_43');
    expect(riderScheme.destination, PushDestination.support);
  });

  test('a support link only counts for the support_reply kind', () {
    final other = PushPayload.fromMap({
      'kind': 'account.updated',
      'deepLink': 'movera://support/tck_42',
    });
    expect(other.routedTicketId, isNull);
    expect(other.destination, PushDestination.notifications);
  });

  test('an unknown link still falls back to the Notifications list', () {
    final unknown = PushPayload.fromMap({
      'kind': 'support_reply',
      'deepLink': 'https://example.com/support/tck_42',
    });
    expect(unknown.routedTicketId, isNull);
    expect(unknown.destination, PushDestination.notifications);

    final noTicket = PushPayload.fromMap({
      'kind': 'support_reply',
      'deepLink': 'movera://support',
    });
    expect(noTicket.destination, PushDestination.notifications);

    final tripLink = PushPayload.fromMap({
      'kind': 'trip_update',
      'tripId': 'trip-1',
      'deepLink': 'movera://trips/trip-1',
    });
    expect(tripLink.destination, PushDestination.ride);
    expect(tripLink.routedRideId, 'trip-1');
  });

  test('tapping a support_reply push opens the ticket', () async {
    final push = _FakePushService();
    addTearDown(push.opened.close);
    final opened = <String>[];
    var notificationOpens = 0;
    final coordinator = PushCoordinator(
      push: push,
      notifications: NotificationsController(
        store: NotificationsRepository(now: () => DateTime(2026, 11, 9)),
      ),
      openRide: (_) async => fail('not a ride push'),
      openSupport: (ticketId) async {
        opened.add(ticketId);
        return true;
      },
      openNotifications: () => notificationOpens += 1,
    );
    addTearDown(coordinator.stop);
    await coordinator.start();

    push.opened.add(
      PushPayload.fromMap({
        'kind': 'support_reply',
        'notificationId': 'n-1',
        'deepLink': 'movera://support/tck_42',
      }),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(opened, ['tck_42']);
    expect(notificationOpens, 0);
  });

  test(
    'a support_reply push that cannot open falls back to the list',
    () async {
      final push = _FakePushService();
      addTearDown(push.opened.close);
      var notificationOpens = 0;
      final coordinator = PushCoordinator(
        push: push,
        notifications: NotificationsController(
          store: NotificationsRepository(now: () => DateTime(2026, 11, 9)),
        ),
        openRide: (_) async => fail('not a ride push'),
        openSupport: (_) async => false,
        openNotifications: () => notificationOpens += 1,
      );
      addTearDown(coordinator.stop);
      await coordinator.start();

      push.opened.add(
        PushPayload.fromMap({
          'kind': 'support_reply',
          'deepLink': 'movera://support/tck_42',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(notificationOpens, 1);
    },
  );
}
