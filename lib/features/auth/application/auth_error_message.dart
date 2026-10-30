import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// What the rider was doing when sign-in failed.
enum AuthAction { sendCode, verifyCode, providerSignIn }

/// Contract v0.15.0 `429 rate_limited`, reason `otp_too_many_attempts`.
bool isTooManyWrongCodes(Object error) =>
    error is ApiError && error.detail == 'otp_too_many_attempts';

/// The contract's reason for a wrong code (`400 invalid_request`, reason
/// `invalid_otp_code`; `invalid_otp` is an older alias).
bool isWrongCode(Object error) =>
    error is ApiError &&
    (error.detail == 'invalid_otp_code' || error.detail == 'invalid_otp');

/// Contract v0.15.0 `403 forbidden`, reason `sign_in_restricted`: the number
/// can join the waiting list (owner 2026-10-29, decision 5).
bool isSignInRestricted(Object error) =>
    error is ApiError && error.detail == 'sign_in_restricted';

/// Owner 2026-10-29, decision 4 (`fixtures/sign_in.json#waitDisplay`): a
/// wait under one minute in seconds, else in whole minutes rounded up
/// ("42 min").
String authWaitText(Duration wait) {
  final seconds = wait.inSeconds + (wait.inMilliseconds % 1000 == 0 ? 0 : 1);
  if (seconds < 60) return L10n.current.retrySeconds(seconds);
  return L10n.current.retryMinutes((seconds + 59) ~/ 60);
}

/// A specific, honest message for a sign-in failure.
///
/// The old screens said "That verification code is not valid" for every
/// failure, including no connection. Riders now learn whether the code was
/// wrong, expired, rate limited, or never reached the server.
String authErrorMessage(Object error, AuthAction action, {String? provider}) {
  switch (riderErrorKind(error)) {
    case RiderErrorKind.offline:
      return L10n.current.errOffline;
    case RiderErrorKind.rateLimited:
      if (isTooManyWrongCodes(error)) {
        return L10n.current.errTooManyWrongCodes(L10n.current.resendCode);
      }
      final wait = error is ApiError ? error.retryAfter : null;
      return wait == null || wait <= Duration.zero
          ? L10n.current.errTooManyWait
          : L10n.current.errTooManyIn(authWaitText(wait));
    case RiderErrorKind.serverTrouble:
      return L10n.current.errServer;
    case RiderErrorKind.refused:
    case RiderErrorKind.unknown:
      break;
  }
  if (error is ApiError) {
    // R-O4: the contract code (`invalid_request`, `unauthenticated`) with
    // the server's lower-case reason beside it.
    switch (error.detail) {
      // The contract's reason for a wrong code (400 invalid_request);
      // `invalid_otp` stays as a harmless older alias.
      case 'invalid_otp_code':
      case 'invalid_otp':
        return L10n.current.errWrongCode;
      case 'otp_expired':
      case 'invalid_otp_session':
        return L10n.current.codeExpired;
      case 'invalid_phone':
        return L10n.current.invalidMobileNumber;
      case 'sign_in_restricted':
        return L10n.current.signInRestricted;
    }
  }
  return switch (action) {
    AuthAction.sendCode => L10n.current.errSendCode,
    AuthAction.verifyCode => L10n.current.errCheckCode,
    AuthAction.providerSignIn => L10n.current.errProvider(
      provider ?? L10n.current.thatAccount,
    ),
  };
}
