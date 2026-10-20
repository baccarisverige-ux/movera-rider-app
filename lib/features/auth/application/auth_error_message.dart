import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/rider_error_kind.dart';

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
      return 'No connection. Check your internet and try again.';
    case RiderErrorKind.rateLimited:
      final wait = riderRetryWait(error);
      return wait == null
          ? 'Too many tries. Wait a moment and try again.'
          : 'Too many tries. Try again in $wait.';
    case RiderErrorKind.serverTrouble:
      return 'Movera is having trouble right now. Try again in a moment.';
    case RiderErrorKind.refused:
    case RiderErrorKind.unknown:
      break;
  }
  if (error is ApiError) {
    // R-O4: the contract code (`invalid_request`, `unauthenticated`) with
    // the server's lower-case reason beside it.
    switch (error.detail) {
      case 'invalid_otp':
        return "That code isn't right. Check it and try again.";
      case 'otp_expired':
      case 'invalid_otp_session':
        return 'This code has expired. Tap Resend code for a new one.';
      case 'invalid_phone':
        return 'Enter a valid Swedish mobile number.';
    }
  }
  return switch (action) {
    AuthAction.sendCode => "Couldn't send the code. Try again.",
    AuthAction.verifyCode => "Couldn't check the code. Try again.",
    AuthAction.providerSignIn =>
      "Couldn't sign in with ${provider ?? 'that account'}. Try again.",
  };
}
