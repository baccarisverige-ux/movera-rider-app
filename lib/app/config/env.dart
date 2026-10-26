import 'package:flutter/foundation.dart';

enum AppFlavor { demo, dev, test, staging, production }

class AppEnv {
  const AppEnv({
    required this.flavor,
    required this.apiBaseUrl,
    bool? authRequired,
    this.firebaseApiKey = '',
    this.firebaseAppId = '',
    this.firebaseMessagingSenderId = '',
    this.firebaseProjectId = '',
    this.firebaseVapidKey = '',
  }) : authRequired =
           authRequired ??
           (flavor == AppFlavor.staging || flavor == AppFlavor.production);

  final AppFlavor flavor;
  final String apiBaseUrl;
  final bool authRequired;
  final String firebaseApiKey;
  final String firebaseAppId;
  final String firebaseMessagingSenderId;
  final String firebaseProjectId;
  final String firebaseVapidKey;

  static const _flavorName = String.fromEnvironment(
    'MOVERA_FLAVOR',
    defaultValue: 'demo',
  );

  static const current = AppEnv(
    flavor: _flavorName == 'production'
        ? AppFlavor.production
        : _flavorName == 'staging'
        ? AppFlavor.staging
        : _flavorName == 'test'
        ? AppFlavor.test
        : _flavorName == 'dev'
        ? AppFlavor.dev
        : AppFlavor.demo,
    apiBaseUrl: String.fromEnvironment(
      'MOVERA_API_BASE_URL',
      defaultValue: 'https://api.demo.movera.invalid',
    ),
    authRequired: bool.fromEnvironment(
      'MOVERA_AUTH_REQUIRED',
      defaultValue: _flavorName == 'staging' || _flavorName == 'production',
    ),
    firebaseApiKey: String.fromEnvironment('MOVERA_FIREBASE_API_KEY'),
    firebaseAppId: String.fromEnvironment('MOVERA_FIREBASE_APP_ID'),
    firebaseMessagingSenderId: String.fromEnvironment(
      'MOVERA_FIREBASE_MESSAGING_SENDER_ID',
    ),
    firebaseProjectId: String.fromEnvironment('MOVERA_FIREBASE_PROJECT_ID'),
    firebaseVapidKey: String.fromEnvironment('MOVERA_FIREBASE_VAPID_KEY'),
  );

  static AppFlavor parseFlavor(String value) {
    return AppFlavor.values.firstWhere(
      (flavor) => flavor.name == value.trim().toLowerCase(),
      orElse: () => AppFlavor.demo,
    );
  }

  /// Explicit web preview of the mock sign-in flow; never enables it in release builds.
  bool get authPreview =>
      kIsWeb &&
      flavor == AppFlavor.demo &&
      Uri.base.queryParameters['auth_preview'] == '1';

  bool get isProduction => flavor == AppFlavor.production;
  bool get isReleaseLike =>
      flavor == AppFlavor.staging || flavor == AppFlavor.production;

  bool get hasFirebaseConfig =>
      firebaseApiKey.trim().isNotEmpty &&
      firebaseAppId.trim().isNotEmpty &&
      firebaseMessagingSenderId.trim().isNotEmpty &&
      firebaseProjectId.trim().isNotEmpty;

  bool get allowsMockTransport =>
      flavor == AppFlavor.demo ||
      flavor == AppFlavor.dev ||
      flavor == AppFlavor.test;
}
