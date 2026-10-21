import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/notifications/firebase_push_service.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';

class _FakeGateway implements FirebasePushGateway {
  final StreamController<String> refresh = StreamController<String>.broadcast();
  final StreamController<PushPayload> foreground =
      StreamController<PushPayload>.broadcast();
  final StreamController<PushPayload> opened =
      StreamController<PushPayload>.broadcast();
  PushPayload? initial;
  PushAuthorizationStatus authorization = PushAuthorizationStatus.authorized;
  String? token = 'fcm-token-a';
  int initializeCalls = 0;
  int deleteCalls = 0;

  @override
  Future<void> initialize(AppEnv environment) async {
    initializeCalls += 1;
  }

  @override
  Future<PushAuthorizationStatus> requestPermission() async => authorization;

  @override
  Future<void> ensureAppleTransportReady() async {}

  @override
  Future<String?> getToken({String? vapidKey}) async => token;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<PushPayload> get onForegroundMessage => foreground.stream;

  @override
  Stream<PushPayload> get onOpenedMessage => opened.stream;

  @override
  Future<PushPayload?> getInitialMessage() async => initial;

  @override
  Future<void> deleteToken() async {
    deleteCalls += 1;
  }

  Future<void> dispose() async {
    await refresh.close();
    await foreground.close();
    await opened.close();
  }
}

const _production = AppEnv(
  flavor: AppFlavor.production,
  apiBaseUrl: 'https://api.movera.example',
  firebaseApiKey: 'api-key',
  firebaseAppId: 'app-id',
  firebaseMessagingSenderId: 'sender-id',
  firebaseProjectId: 'project-id',
);

void main() {
  test('Phase 78 registers, rotates and unregisters the authoritative push token',
      () async {
    final backend = InProcessMockClient();
    final gateway = _FakeGateway();
    addTearDown(gateway.dispose);
    final service = FirebasePushService(
      api: ApiClient(env: _production, client: backend),
      environment: _production,
      gateway: gateway,
    );
    addTearDown(service.dispose);

    await service.register();

    expect(gateway.initializeCalls, 1);
    expect(backend.pushDevices['fcm-token-a']?['platform'], isNotEmpty);

    gateway.refresh.add('fcm-token-b');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(backend.pushDevices.containsKey('fcm-token-a'), isFalse);
    expect(backend.pushDevices['fcm-token-b']?['provider'], 'fcm');

    await service.unregister();

    expect(backend.pushDevices, isEmpty);
    expect(gateway.deleteCalls, 1);
  });

  test('Phase 78 fails closed when notification permission is denied', () async {
    final backend = InProcessMockClient();
    final gateway = _FakeGateway()
      ..authorization = PushAuthorizationStatus.denied;
    addTearDown(gateway.dispose);
    final service = FirebasePushService(
      api: ApiClient(env: _production, client: backend),
      environment: _production,
      gateway: gateway,
    );
    addTearDown(service.dispose);

    await expectLater(
      service.register(),
      throwsA(isA<PushPermissionDeniedException>()),
    );

    expect(backend.pushDevices, isEmpty);
  });

  test('Phase 78 release push rejects missing Firebase configuration', () async {
    const missing = AppEnv(
      flavor: AppFlavor.production,
      apiBaseUrl: 'https://api.movera.example',
    );
    final gateway = _FakeGateway();
    addTearDown(gateway.dispose);
    final service = FirebasePushService(
      api: ApiClient(env: missing, client: InProcessMockClient()),
      environment: missing,
      gateway: gateway,
    );
    addTearDown(service.dispose);

    await expectLater(
      service.register(),
      throwsA(isA<PushConfigurationException>()),
    );
    expect(gateway.initializeCalls, 0);
  });

  test('Phase 78 deletes the local FCM token when server unregister fails',
      () async {
    final backend = InProcessMockClient();
    final gateway = _FakeGateway();
    addTearDown(gateway.dispose);
    final service = FirebasePushService(
      api: ApiClient(env: _production, client: backend),
      environment: _production,
      gateway: gateway,
    );
    addTearDown(service.dispose);

    await service.register();
    backend.failNext = true;

    await expectLater(service.unregister(), throwsA(anything));

    expect(gateway.deleteCalls, 1);
  });

  test('rider-u21: inbound pushes still route when the token POST fails',
      () async {
    const launch = PushPayload(type: 'ride_update', rideId: 'r1');
    const tap = PushPayload(type: 'driver_arrived', rideId: 'r1');
    final backend = InProcessMockClient()..failNext = true;
    final gateway = _FakeGateway()..initial = launch;
    addTearDown(gateway.dispose);
    final service = FirebasePushService(
      api: ApiClient(env: _production, client: backend),
      environment: _production,
      gateway: gateway,
    );
    addTearDown(service.dispose);
    final opened = <PushPayload>[];
    final sub = service.openedMessages.listen(opened.add);
    addTearDown(sub.cancel);

    await expectLater(service.register(), throwsA(anything));

    expect(backend.pushDevices, isEmpty);
    expect(await service.takeInitialMessage(), same(launch));
    gateway.opened.add(tap);
    await pumpEventQueue();
    expect(opened, [same(tap)]);
  });
}
