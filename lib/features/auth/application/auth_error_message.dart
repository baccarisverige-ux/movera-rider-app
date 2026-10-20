import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// What the rider was doing when sign-in failed.
enum AuthAction { sendCode, verifyCode, providerSignIn }

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
      final wait = riderRetryWait(error);
      return wait == null
          ? L10n.current.errTooManyWait
          : L10n.current.errTooManyIn(wait);
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
      case 'invalid_otp':
        return L10n.current.errWrongCode;
      case 'otp_expired':
      case 'invalid_otp_session':
        return L10n.current.codeExpired;
      case 'invalid_phone':
        return L10n.current.invalidSwedishMobile;
    }
  }
  return switch (action) {
    AuthAction.sendCode => L10n.current.errSendCode,
    AuthAction.verifyCode => L10n.current.errCheckCode,
    AuthAction.providerSignIn =>
      L10n.current.errProvider(provider ?? L10n.current.thatAccount),
  };
}
