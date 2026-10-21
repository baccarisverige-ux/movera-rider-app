class OtpChallenge {
  const OtpChallenge({
    required this.phone,
    required this.requestId,
    required this.sessionId,
    required this.expiresAt,
    required this.retryAfter,
    this.link,
  });

  final String phone;
  final String requestId;
  final String sessionId;
  final DateTime expiresAt;
  final Duration retryAfter;

  /// Set when this code confirms the phone of an Apple or Google sign-in
  /// that is still waiting for a verified number.
  final ProviderLink? link;

  /// Measured with the device clock, which can run ahead of the server's:
  /// a hint only. rider-u73: nothing refuses to send a code because of it;
  /// the server answers `410 otp_expired` for a code that really expired.
  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  Duration get remaining {
    final value = expiresAt.difference(DateTime.now().toUtc());
    return value.isNegative ? Duration.zero : value;
  }
}

/// An Apple or Google sign-in the backend accepted but will not finish until
/// the rider verifies a phone number. It carries no session: the app holds
/// only this short-lived link token and saves real tokens once the phone code
/// is verified, so leaving half-way never leaves a phone-less session behind.
class ProviderLink {
  const ProviderLink({
    required this.provider,
    required this.linkToken,
    this.name,
  });

  /// 'apple' or 'google'.
  final String provider;
  final String linkToken;

  /// The rider's name as shared by Apple or Google, when it was.
  final String? name;

  String get providerLabel => provider == 'apple' ? 'Apple' : 'Google';
}

/// Outcome of a verified phone code.
class OtpVerifyResult {
  const OtpVerifyResult({required this.isNewRider});

  /// The backend has no profile for this rider yet, so the app asks for a
  /// name before the map. Missing from the response means a returning rider.
  final bool isNewRider;
}

/// Outcome of an Apple or Google sign-in.
sealed class ProviderSignInResult {
  const ProviderSignInResult();
}

/// Signed in: the account already has a verified phone.
class ProviderSignedIn extends ProviderSignInResult {
  const ProviderSignedIn();
}

/// First time with this provider: a phone number must be added and verified.
class ProviderPhoneRequired extends ProviderSignInResult {
  const ProviderPhoneRequired(this.link);

  final ProviderLink link;
}
