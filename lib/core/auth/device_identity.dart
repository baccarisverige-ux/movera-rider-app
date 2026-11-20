import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contract v0.18.138 (`contract.json#deviceCheck`; owner 2026-11-20 "Ok"):
/// what the code request carries against SMS abuse.
///
/// - `installId`: a random id made once per app install and kept in the
///   app's own storage (never a hardware id); the server allows at most
///   `countryLimits.codesPerDevicePerHour` codes per install per hour.
/// - `deviceCheck`: proof that this is the real store app on a real phone,
///   bound to app + number + install (`deviceCheck.binding`): Google Play
///   Integrity on Android; Apple App Attest on iPhone, which stays OFF until
///   the owner's Apple account exists (build flag `APP_ATTEST=true`, see
///   [DeviceIdentity.appAttestEnabled]). The server asks for it only where
///   the country's "Require device check" is on.
///
/// Any failure here sends the request without a check: the server decides.
class DeviceIdentity {
  DeviceIdentity({
    Future<SharedPreferences> Function()? prefs,
    MethodChannel? channel,
    TargetPlatform? platform,
    bool? isWeb,
    bool? appAttest,
    Random? random,
    Duration timeout = const Duration(seconds: 8),
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _channel = channel ?? const MethodChannel(channelName),
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb,
       _appAttest = appAttest ?? appAttestEnabled,
       _random = random ?? Random.secure(),
       _timeout = timeout;

  static const channelName = 'movera/device_check';

  /// The app's one instance (sign-in and phone change share the install id).
  static final DeviceIdentity app = DeviceIdentity();
  static const storageKey = 'movera.installId';

  /// iPhone App Attest: INACTIVE until the owner's Apple account exists
  /// (contract `deviceCheck.ios.active` false). A build made with
  /// `--dart-define=APP_ATTEST=true` (and the App Attest capability) turns it on.
  static const appAttestEnabled = bool.fromEnvironment('APP_ATTEST');

  static final _shape = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

  final Future<SharedPreferences> Function() _prefs;
  final MethodChannel _channel;
  final TargetPlatform _platform;
  final bool _isWeb;
  final bool _appAttest;
  final Random _random;
  final Duration _timeout;
  String? _id;

  /// The install id: read once, made (32 hex digits) and kept on first use.
  /// Storage failing gives an id for this run only.
  Future<String> installId() async {
    final known = _id;
    if (known != null) return known;
    SharedPreferences? store;
    try {
      store = await _prefs();
      final saved = store.getString(storageKey);
      if (saved != null && _shape.hasMatch(saved)) return _id = saved;
    } catch (_) {}
    final made = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    try {
      await store?.setString(storageKey, made);
    } catch (_) {}
    return _id = made;
  }

  /// Contract `deviceCheck.binding`.
  static List<int> binding(String app, String phone, String installId) => sha256
      .convert(utf8.encode('movera-sms-code|$app|$phone|$installId'))
      .bytes;

  /// The `deviceCheck` object for the request, or null (web, iPhone while
  /// App Attest is off, no Play services, a time-out, any error).
  Future<Map<String, String>?> check(
    String app,
    String phone,
    String installId,
  ) async {
    if (_isWeb) return null;
    final bound = binding(app, phone, installId);
    try {
      switch (_platform) {
        case TargetPlatform.android:
          final nonce = base64Url.encode(bound).replaceAll('=', '');
          final token = await _channel
              .invokeMethod<String>('playIntegrity', {'nonce': nonce})
              .timeout(_timeout);
          if (token == null || token.isEmpty) return null;
          return {'platform': 'android', 'token': token};
        case TargetPlatform.iOS:
          if (!_appAttest) return null;
          final answer = await _channel
              .invokeMapMethod<String, String>('appAttest', {
                'clientDataHash': base64.encode(bound),
              })
              .timeout(_timeout);
          final token = answer?['attestation'];
          final keyId = answer?['keyId'];
          if (token == null ||
              token.isEmpty ||
              keyId == null ||
              keyId.isEmpty) {
            return null;
          }
          return {'platform': 'ios', 'token': token, 'keyId': keyId};
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// The two fields for `POST /auth/otp/request`.
  Future<Map<String, Object>> requestFields(String app, String phone) async {
    final id = await installId();
    final proof = await check(app, phone, id);
    return {'installId': id, if (proof != null) 'deviceCheck': proof};
  }
}
