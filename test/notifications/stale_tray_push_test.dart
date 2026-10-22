import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/application/push_coordinator.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Push implements PushService {
  final opened = StreamController<PushPayload>.broadcast();
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

/// rider-r5-44: a tray notification sent before this rider signed in on
/// the device (the previous rider's) never enters this rider's feed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a previous rider\'s tapped notification is dropped', () async {
    SharedPreferences.setMockInitialValues({});
    await UserDataWipe.enterSessionAs('phone:+46709876543');
    final push = _Push();
    final store = NotificationsRepository();
    final coordinator = PushCoordinator(
      push: push,
      notifications: NotificationsController(store: store),
      openRide: (_) async => false,
      openNotifications: () {},
    );
    addTearDown(coordinator.stop);
    await coordinator.start();

    push.opened.add(PushPayload(
      type: 'ride.driver_arriving',
      rideId: 'ride-of-rider-a',
      title: 'Ahmed is arriving',
      body: 'At Storgatan 5',
      messageId: 'a-1',
      sentAt: DateTime.now().subtract(const Duration(hours: 1)),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(store.all(), isEmpty);
  });
}
