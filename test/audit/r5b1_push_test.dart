import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/notifications/firebase_push_service.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/features/notifications/application/notifications_controller.dart';
import 'package:movera_rider/features/notifications/application/push_coordinator.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';

class _Gateway implements FirebasePushGateway {
  final opened = StreamController<PushPayload>.broadcast();
  PushPayload? initial;
  int deletes = 0;
  @override
  Future<void> initialize(AppEnv environment) async {}
  @override
  Future<PushAuthorizationStatus> requestPermission() async =>
      PushAuthorizationStatus.authorized;
  @override
  Future<void> ensureAppleTransportReady() async {}
  @override
  Future<String?> getToken({String? vapidKey}) async => 'tok';
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<PushPayload> get onForegroundMessage => const Stream.empty();
  @override
  Stream<PushPayload> get onOpenedMessage => opened.stream;
  @override
  Future<PushPayload?> getInitialMessage() async => initial;
  @override
  Future<void> deleteToken() async => deletes += 1;
}

const _env = AppEnv(
  flavor: AppFlavor.production,
  apiBaseUrl: 'https://api.movera.example',
  firebaseApiKey: 'k',
  firebaseAppId: 'a',
  firebaseMessagingSenderId: 's',
  firebaseProjectId: 'p',
);

void main() {
  test('rider-r5-40: a cold-start tap opens even when register() runs after '
      'the coordinator started', () async {
    final gateway = _Gateway()
      ..initial = const PushPayload(type: 'ride.driver_assigned', rideId: 'ride-1');
    final service = FirebasePushService(
      api: ApiClient(env: _env, client: InProcessMockClient()),
      environment: _env,
      gateway: gateway,
    );
    final opened = <String>[];
    final coordinator = PushCoordinator(
      push: service,
      openRide: (id) async {
        opened.add(id);
        return true;
      },
      openNotifications: () {},
      notifications: NotificationsController(
        store: NotificationsRepository(),
      ),
    );
    await coordinator.start();
    await service.register();
    await pumpEventQueue();
    expect(opened, ['ride-1']);
  });
}
