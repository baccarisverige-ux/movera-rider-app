import 'dart:async';

import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/auth/application/pending_rider_name.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/core/notifications/push_permission_gate.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';

class AuthController {
  AuthController({AuthRepository? auth, PushPermissionGate? pushPermission})
    : _auth = auth ?? AuthRepository(),
      _pushPermission = pushPermission;

  final AuthRepository _auth;
  final PushPermissionGate? _pushPermission;
  OtpChallenge? lastChallenge;

  String? get lastPhone => lastChallenge?.phone;

  Future<OtpChallenge> requestOtp({
    required String phone,
    ProviderLink? link,
  }) async {
    final challenge = await _auth.requestOtp(phone: phone, link: link);
    lastChallenge = challenge;
    return challenge;
  }

  Future<OtpVerifyResult> verifyOtp({
    required OtpChallenge challenge,
    required String code,
  }) async {
    final result = await _auth.verifyOtp(challenge: challenge, code: code);
    lastChallenge = null;
    // rider-r5-31: the new rider's name marker (rider-u74) was written by
    // the verify call; a wipe of the previous rider's data must keep it.
    final pendingName = await PendingRiderName.read();
    await _enterSession(phone: challenge.phone);
    if (pendingName != null) await PendingRiderName.mark(pendingName);
    unawaited(_registerPushBestEffort());
    return result;
  }

  /// Apple or Google. Push registers only once a session exists, which for
  /// a first-time provider rider is after the phone code.
  Future<ProviderSignInResult> signIn({required String provider}) async {
    final result = await _auth.signIn(provider: provider);
    if (result is ProviderSignedIn) {
      await _enterSession(provider: provider);
      unawaited(_registerPushBestEffort());
    }
    return result;
  }

  /// A different rider than the one whose session expired on this device:
  /// wipe the previous rider's data before the app opens (FLOW-1).
  Future<void> _enterSession({String? phone, String? provider}) async {
    try {
      final riderId = UserDataWipe.riderIdFor(
        accessToken: await _auth.readAccessToken(),
        phone: phone,
        provider: provider,
      );
      if (riderId != null) await UserDataWipe.enterSessionAs(riderId);
    } catch (error, stackTrace) {
      AppLog.error(
        'auth.enter_session_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> hasSession() => _auth.hasSession();

  /// Registers push only for a rider who already accepted the in-app
  /// explanation (UI-17); a first sign-in sees the explanation on Home
  /// instead of a cold OS prompt. rider-u67: sign-in does not wait for it
  /// (Firebase, getToken and the device POST can take 15 s or more on a
  /// poor connection); it runs on while the app opens.
  Future<void> _registerPushBestEffort() async {
    try {
      await (_pushPermission ?? AppScope.instance.pushPermission)
          .registerIfConsented(logEvent: 'auth.push_registration_deferred');
    } catch (error) {
      AppLog.warning(
        'auth.push_registration_deferred',
        extra: {'error': error.runtimeType.toString()},
      );
    }
  }

  /// Ends the session and removes everything the rider left on this device
  /// (UserDataWipe), even when the backend cannot be reached.
  Future<void> signOut() async {
    // Queued cancels still go out with this rider's own session.
    await UserDataWipe.flushPendingCancels();
    // Unregister while the access token is still available. Even when the
    // backend is unreachable, FirebasePushService deletes the local token so a
    // signed-out Rider cannot keep receiving notifications for that session.
    try {
      await AppScope.instance.push.unregister();
    } catch (error) {
      AppLog.warning(
        'auth.push_unregister_deferred',
        extra: {'error': error.toString()},
      );
    }
    try {
      await _auth.signOut();
    } finally {
      // Local wipe even when the backend sign-out fails (tokens are cleared
      // the same way in AuthRepository.signOut).
      await UserDataWipe.run();
    }
  }

  /// Ends the session on this device without calling the backend, which has
  /// already ended it (an accepted account deletion revokes the rider's
  /// sessions and push devices). Same local wipe as [signOut].
  Future<void> signOutLocally() async {
    try {
      await _auth.clearLocalSession();
    } finally {
      await UserDataWipe.run();
    }
  }
}
