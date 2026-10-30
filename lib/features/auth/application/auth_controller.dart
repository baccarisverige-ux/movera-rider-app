import 'dart:async';

import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/auth/application/pending_rider_name.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/core/notifications/push_permission_gate.dart';
import 'package:movera_rider/core/auth/signed_out_notice.dart';
import 'package:movera_rider/features/auth/data/auth_repository.dart';
import 'package:movera_rider/features/auth/data/provider_token_source.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/auth/domain/test_account.dart';

class AuthController {
  AuthController({
    AuthRepository? auth,
    PushPermissionGate? pushPermission,
    ProviderTokenSource? providerTokens,
  }) : _auth = auth ?? AuthRepository(),
       _pushPermission = pushPermission,
       _providerTokens = providerTokens ?? const NoProviderTokenSource();

  final AuthRepository _auth;
  final ProviderTokenSource _providerTokens;
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

  /// Apple or Google: the provider's identity token first, then `POST
  /// /auth/provider`. Null when the rider closed the provider's sheet.
  /// Throws [ProviderUnavailable] when this build cannot ask the provider.
  /// Push registers only once a session exists, which for a first-time
  /// provider rider is after the phone code.
  Future<ProviderSignInResult?> signIn({required String provider}) async {
    final token = await _providerTokens.obtain(provider);
    if (token == null) return null;
    final result = await _auth.signIn(
      provider: provider,
      idToken: token.idToken,
      name: token.name,
    );
    if (result is ProviderSignedIn) {
      await _enterSession(provider: provider);
      unawaited(_registerPushBestEffort());
    }
    return result;
  }

  /// A different rider than the one whose session expired on this device:
  /// wipe the previous rider's data before the app opens (FLOW-1).
  Future<void> _enterSession({String? phone, String? provider}) async {
    SignedOutNotice.clear();
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

  /// Contract v0.15.0 (decision 5): `POST /auth/waitlist`.
  Future<void> joinWaitlist({required String phone, String? locale}) =>
      _auth.joinWaitlist(phone: phone, locale: locale);

  /// Contract v0.15.0 (decision 6): the test numbers, test builds only.
  Future<List<TestAccount>> testAccounts() => _auth.testAccounts();

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
    // v0.18.5 auth.signedOut.ownSignOut: no message after the rider's own
    // Sign out.
    SignedOutNotice.clear();
    // v0.18.5 legal: nothing to accept while signed out.
    _legalSignedOut();
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

  static void _legalSignedOut() {
    try {
      AppScope.instance.legal.signedOut();
    } catch (_) {
      // No app scope (tests of the controller alone).
    }
  }

  /// Ends the session on this device without calling the backend, which has
  /// already ended it (an accepted account deletion revokes the rider's
  /// sessions and push devices). Same local wipe as [signOut].
  Future<void> signOutLocally() async {
    _legalSignedOut();
    try {
      await _auth.clearLocalSession();
    } finally {
      await UserDataWipe.run();
    }
  }
}
