import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/notifications/push_payload.dart';
import 'package:movera_rider/core/notifications/push_service.dart';

enum PushAuthorizationStatus { authorized, provisional, denied }

/// Web push service worker shipped in `web/`. It is only registered by
/// [FlutterFirebasePushGateway.getToken], which runs only when Firebase is
/// configured, so builds without Firebase never install it.
const String moveraFirebaseMessagingServiceWorker = 'firebase-messaging-sw.js';

FirebaseOptions _firebaseOptions(AppEnv environment) {
  return FirebaseOptions(
    apiKey: environment.firebaseApiKey,
    appId: environment.firebaseAppId,
    messagingSenderId: environment.firebaseMessagingSenderId,
    projectId: environment.firebaseProjectId,
  );
}

@pragma('vm:entry-point')
Future<void> moveraFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  final environment = AppEnv.current;
  if (!environment.hasFirebaseConfig) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: _firebaseOptions(environment));
  }
  // Background delivery is a wake-up signal only. Ride state remains
  // authoritative from the backend and is reconciled after the Rider opens
  // the notification/app.
}

abstract interface class FirebasePushGateway {
  Future<void> initialize(AppEnv environment);
  Future<PushAuthorizationStatus> requestPermission();
  Future<void> ensureAppleTransportReady();
  Future<String?> getToken({String? vapidKey});
  Stream<String> get onTokenRefresh;
  Stream<PushPayload> get onForegroundMessage;
  Stream<PushPayload> get onOpenedMessage;
  Future<PushPayload?> getInitialMessage();
  Future<void> deleteToken();
}

class FlutterFirebasePushGateway implements FirebasePushGateway {
  FlutterFirebasePushGateway({FirebaseMessaging? messaging})
    : _messagingOverride = messaging;

  final FirebaseMessaging? _messagingOverride;
  FirebaseMessaging get _messaging =>
      _messagingOverride ?? FirebaseMessaging.instance;

  @override
  Future<void> initialize(AppEnv environment) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _firebaseOptions(environment));
    }
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
        moveraFirebaseMessagingBackgroundHandler,
      );
    }
  }

  @override
  Future<PushAuthorizationStatus> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    switch (settings.authorizationStatus) {
      case AuthorizationStatus.authorized:
        return PushAuthorizationStatus.authorized;
      case AuthorizationStatus.provisional:
        return PushAuthorizationStatus.provisional;
      case AuthorizationStatus.denied:
      case AuthorizationStatus.deniedPermanently:
      case AuthorizationStatus.notDetermined:
        return PushAuthorizationStatus.denied;
    }
  }

  @override
  Future<void> ensureAppleTransportReady() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return;
    }
    for (var attempt = 0; attempt < 10; attempt += 1) {
      final token = await _messaging.getAPNSToken();
      if (token != null && token.trim().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw const PushRegistrationException('APNs token is not available yet.');
  }

  @override
  Future<String?> getToken({String? vapidKey}) => _messaging.getToken(
    vapidKey: vapidKey,
    // Relative to the page's <base href>, so the worker also registers
    // when the app is served from a sub-path such as /movera-rider-app/.
    // The Firebase default (/firebase-messaging-sw.js at the origin root)
    // does not exist there.
    serviceWorkerScriptPath: kIsWeb
        ? moveraFirebaseMessagingServiceWorker
        : null,
  );

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<PushPayload> get onForegroundMessage => FirebaseMessaging.onMessage
      .map(_payloadFromRemoteMessage)
      .where((payload) => payload != null)
      .cast<PushPayload>();

  @override
  Stream<PushPayload> get onOpenedMessage => FirebaseMessaging
      .onMessageOpenedApp
      .map(_payloadFromRemoteMessage)
      .where((payload) => payload != null)
      .cast<PushPayload>();

  @override
  Future<PushPayload?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _payloadFromRemoteMessage(message);
  }

  PushPayload? _payloadFromRemoteMessage(RemoteMessage message) {
    try {
      return PushPayload.fromMap(
        message.data,
        messageId: message.messageId,
        title: message.notification?.title,
        body: message.notification?.body,
        sentAt: message.sentTime,
      );
    } on FormatException catch (error) {
      AppLog.warning(
        'push.payload_rejected',
        extra: {'messageId': message.messageId ?? '', 'reason': error.message},
      );
      return null;
    }
  }

  @override
  Future<void> deleteToken() => _messaging.deleteToken();
}

class FirebasePushService implements PushService {
  FirebasePushService({
    required ApiClient api,
    required AppEnv environment,
    FirebasePushGateway? gateway,
  }) : _api = api,
       _environment = environment,
       _gateway = gateway ?? FlutterFirebasePushGateway();

  final ApiClient _api;
  final AppEnv _environment;
  final FirebasePushGateway _gateway;
  final StreamController<PushPayload> _foreground =
      StreamController<PushPayload>.broadcast();
  final StreamController<PushPayload> _opened =
      StreamController<PushPayload>.broadcast();
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<PushPayload>? _foregroundSub;
  StreamSubscription<PushPayload>? _openedSub;
  String? _registeredToken;
  PushPayload? _initialMessage;
  bool _initialRead = false;
  bool _initialTaken = false;

  @override
  Stream<PushPayload> get foregroundMessages => _foreground.stream;

  @override
  Stream<PushPayload> get openedMessages => _opened.stream;

  @override
  Future<void> register() async {
    if (!_environment.hasFirebaseConfig) {
      throw const PushConfigurationException(
        'Firebase push configuration is missing.',
      );
    }
    if (kIsWeb && _environment.firebaseVapidKey.trim().isEmpty) {
      throw const PushConfigurationException(
        'Firebase web push VAPID key is missing.',
      );
    }

    await _gateway.initialize(_environment);
    final permission = await _gateway.requestPermission();
    if (permission == PushAuthorizationStatus.denied) {
      throw const PushPermissionDeniedException();
    }
    // rider-u21: what the OS shows (a tap, a foreground message, the
    // notification that launched the app) is routed whether or not the
    // backend acknowledges the token below. Attached only after that ack,
    // a failed POST at cold start dropped the launch tap and every later one.
    await _attachInboundStreams();

    await _gateway.ensureAppleTransportReady();
    final token = await _gateway.getToken(
      vapidKey: kIsWeb ? _environment.firebaseVapidKey : null,
    );
    if (token == null || token.trim().isEmpty) {
      throw const PushRegistrationException(
        'Firebase did not return a device token.',
      );
    }

    await _replaceToken(token.trim());
    await _tokenSub?.cancel();
    _tokenSub = _gateway.onTokenRefresh.listen((next) {
      final normalized = next.trim();
      if (normalized.isEmpty || normalized == _registeredToken) return;
      unawaited(
        _replaceToken(normalized).catchError((Object error, StackTrace stack) {
          AppLog.error(
            'push.token_refresh_failed',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    });
  }

  Future<void> _attachInboundStreams() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _foregroundSub = _gateway.onForegroundMessage.listen(
      _foreground.add,
      onError: (Object error, StackTrace stack) {
        AppLog.error(
          'push.foreground_stream_failed',
          error: error,
          stackTrace: stack,
        );
      },
    );
    _openedSub = _gateway.onOpenedMessage.listen(
      _opened.add,
      onError: (Object error, StackTrace stack) {
        AppLog.error(
          'push.opened_stream_failed',
          error: error,
          stackTrace: stack,
        );
      },
    );
    // rider-r5-40: the launch notification is read once. At cold start the
    // coordinator already asked for it before register() ran, so a late one
    // is routed as a tap instead of waiting for a read that never comes.
    if (_initialRead) return;
    _initialRead = true;
    final initial = await _gateway.getInitialMessage();
    if (initial == null) return;
    if (_initialTaken) {
      _opened.add(initial);
    } else {
      _initialMessage = initial;
    }
  }

  @override
  Future<PushPayload?> takeInitialMessage() async {
    _initialTaken = true;
    final initial = _initialMessage;
    _initialMessage = null;
    return initial;
  }

  /// rider-r4-23: the new token is registered first and the old one is
  /// then removed best effort. Unregistering first let a 404 (the backend
  /// already dropped a token FCM reported dead) or any API failure abort
  /// the rotation and leave the device on the dead token.
  Future<void> _replaceToken(String token) async {
    final previous = _registeredToken;

    final response = await _api.post(
      '/api/v1/push/devices',
      body: {'token': token, 'provider': 'fcm', 'platform': _platformName},
    );
    if (response['code'] != 'OK' || response['status'] != 'registered') {
      throw const PushRegistrationException(
        'Push token registration was not acknowledged.',
      );
    }
    _registeredToken = token;

    if (previous != null && previous != token) {
      try {
        await _unregisterToken(previous);
      } catch (error) {
        AppLog.warning(
          'push.old_token_unregister_failed',
          extra: {'error': error.runtimeType.toString()},
        );
      }
    }
  }

  Future<void> _unregisterToken(String token) async {
    final response = await _api.post(
      '/api/v1/push/devices/unregister',
      body: {'token': token},
    );
    if (response['code'] != 'OK' || response['status'] != 'unregistered') {
      throw const PushRegistrationException(
        'Push token removal was not acknowledged.',
      );
    }
    if (_registeredToken == token) _registeredToken = null;
  }

  @override
  Future<void> unregister() async {
    await _tokenSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _tokenSub = null;
    _foregroundSub = null;
    _openedSub = null;
    _initialMessage = null;

    final token = _registeredToken;
    Object? unregisterError;
    StackTrace? unregisterStack;
    if (token != null) {
      try {
        await _unregisterToken(token);
      } catch (error, stack) {
        unregisterError = error;
        unregisterStack = stack;
      }
    }

    try {
      await _gateway.deleteToken();
    } finally {
      _registeredToken = null;
    }

    if (unregisterError != null) {
      Error.throwWithStackTrace(
        unregisterError,
        unregisterStack ?? StackTrace.current,
      );
    }
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _tokenSub = null;
    _foregroundSub = null;
    _openedSub = null;
    await _foreground.close();
    await _opened.close();
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }
}

class PushConfigurationException implements Exception {
  const PushConfigurationException(this.message);
  final String message;

  @override
  String toString() => 'PushConfigurationException($message)';
}

class PushPermissionDeniedException implements Exception {
  const PushPermissionDeniedException();

  @override
  String toString() => 'PushPermissionDeniedException';
}

class PushRegistrationException implements Exception {
  const PushRegistrationException(this.message);
  final String message;

  @override
  String toString() => 'PushRegistrationException($message)';
}
