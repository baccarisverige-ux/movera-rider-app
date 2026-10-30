import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/notifications/firebase_push_service.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/web/web_push_open.dart';

/// Contract v0.18.3 (owner decision R7): the live web build has no Firebase
/// key of its own; it reads the public settings from the server
/// (`GET /push/config?app=rider`) and registers its FCM token with
/// movera-server's real `PushDeviceAck` answer.
class _Gateway implements FirebasePushGateway {
  AppEnv? initializedWith;
  String? vapidAsked = 'unset';
  int tokenCalls = 0;
  PushAuthorizationStatus authorization = PushAuthorizationStatus.authorized;

  @override
  Future<void> initialize(AppEnv environment) async =>
      initializedWith = environment;

  @override
  Future<PushAuthorizationStatus> requestPermission() async => authorization;

  @override
  Future<void> ensureAppleTransportReady() async {}

  @override
  Future<String?> getToken({String? vapidKey}) async {
    tokenCalls++;
    vapidAsked = vapidKey;
    return 'fcm-rider-1';
  }

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();

  @override
  Stream<PushPayload> get onForegroundMessage => const Stream.empty();

  @override
  Stream<PushPayload> get onOpenedMessage => const Stream.empty();

  @override
  Future<PushPayload?> getInitialMessage() async => null;

  @override
  Future<void> deleteToken() async {}
}

const _live = AppEnv(
  flavor: AppFlavor.production,
  apiBaseUrl: 'https://api.movera.example',
);

void main() {
  late List<http.Request> seen;
  late Map<String, Object?> config;

  ApiClient api() => ApiClient(
    env: _live,
    client: MockClient((request) async {
      seen.add(request);
      final Object body;
      if (request.url.path == '/api/v1/push/config') {
        body = config;
      } else if (request.url.path == '/api/v1/push/devices') {
        // movera-server's PushDeviceAck: no `code`.
        body = {'status': 'registered', 'requestId': 'r1'};
      } else {
        body = {'status': 'unregistered', 'requestId': 'r2'};
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  setUp(() {
    seen = [];
    config = {
      'provider': 'fcm',
      'enabled': true,
      'projectId': 'movera-test',
      'webConfig': {
        'apiKey': 'public-web-key',
        'appId': '1:42:web:rider',
        'messagingSenderId': '42',
        'projectId': 'movera-test',
      },
    };
  });

  test('no Firebase defines: the server settings start Firebase, the token '
      'registers against the real server answer', () async {
    final gateway = _Gateway();
    final service = FirebasePushService(
      api: api(),
      environment: _live,
      gateway: gateway,
    );
    addTearDown(service.dispose);
    await service.register();
    expect(
      seen.first.url.toString(),
      endsWith('/api/v1/push/config?app=rider'),
    );
    expect(gateway.initializedWith?.firebaseApiKey, 'public-web-key');
    expect(gateway.initializedWith?.firebaseAppId, '1:42:web:rider');
    expect(gateway.initializedWith?.firebaseProjectId, 'movera-test');
    expect(gateway.vapidAsked, isNull);
    final register = seen.firstWhere(
      (r) => r.url.path == '/api/v1/push/devices',
    );
    expect(jsonDecode(register.body), {
      'token': 'fcm-rider-1',
      'provider': 'fcm',
      'platform': 'android',
    });
    await service.unregister();
    expect(seen.last.url.path, '/api/v1/push/devices/unregister');
  });

  test('push off on the server: nothing is asked of the browser', () async {
    config = {'provider': 'fcm', 'enabled': false};
    final gateway = _Gateway();
    final service = FirebasePushService(
      api: api(),
      environment: _live,
      gateway: gateway,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.register(),
      throwsA(isA<PushConfigurationException>()),
    );
    expect(gateway.initializedWith, isNull);
    expect(gateway.tokenCalls, 0);
  });

  test('the server push data reads as a payload: kind is its type, '
      'notificationId its id', () {
    final payload = PushPayload.fromMap({
      'notificationId': 'ntf_7',
      'kind': 'trip_message',
      'deepLink': '',
      'title': 'Nytt meddelande',
      'body': 'Hej',
    });
    expect(payload.type, 'trip_message');
    expect(payload.messageId, 'ntf_7');
    expect(payload.title, 'Nytt meddelande');
    expect(payload.destination, PushDestination.notifications);
  });

  test('a web tap from the service worker becomes an opened payload', () {
    final launch = pushFromLaunchQuery({
      'movera_push': 'ntf_9',
      'movera_kind': 'ride.driver_arrived',
      'movera_link': 'movera://ride/r9',
    });
    expect(launch?.messageId, 'ntf_9');
    expect(launch?.routedRideId, 'r9');
    expect(pushFromLaunchQuery({'other': '1'}), isNull);
    expect(
      pushFromOpenMessage({'notificationId': 'ntf_1', 'kind': null})?.type,
      'notification',
    );
    expect(takeWebLaunchPush(), isNull);
  });
}
