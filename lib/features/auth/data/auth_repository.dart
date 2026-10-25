import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/application/pending_rider_name.dart';
import 'package:movera_rider/features/auth/domain/otp_challenge.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';

class AuthRepository {
  AuthRepository({ApiClient? api, TokenStore? tokens})
      : _api = api ?? AppScope.instance.api,
        _tokens = tokens ?? AppScope.instance.tokens;

  final ApiClient _api;
  final TokenStore _tokens;

  /// Sends a 4-digit code to [phone]. With [link], the code also confirms the
  /// phone number of that pending Apple or Google sign-in.
  Future<OtpChallenge> requestOtp({
    required String phone,
    ProviderLink? link,
  }) async {
    final normalized = phone.replaceAll(' ', '').trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(phone, 'phone', 'Phone number is required.');
    }
    final response = await _api.post(
      '/api/v1/auth/otp/request',
      body: {
        'phone': normalized,
        // Contract §8 OtpRequest: which app signs in decides the tokens' actor.
        'app': 'rider',
        if (link != null) 'linkToken': link.linkToken,
      },
    );
    final requestId = response['requestId'];
    final sessionId = response['sessionId'];
    final expiresAt = DateTime.tryParse('${response['expiresAt'] ?? ''}');
    final retryAfterSeconds = (response['retryAfterSeconds'] as num?)?.toInt();
    if (requestId is! String ||
        requestId.isEmpty ||
        sessionId is! String ||
        sessionId.isEmpty ||
        expiresAt == null ||
        retryAfterSeconds == null ||
        retryAfterSeconds < 0) {
      throw StateError('OTP request response was incomplete.');
    }
    return OtpChallenge(
      phone: normalized,
      requestId: requestId,
      sessionId: sessionId,
      expiresAt: expiresAt.toUtc(),
      retryAfter: Duration(seconds: retryAfterSeconds),
      link: link,
    );
  }

  /// Verifies [code] and saves the session only after the backend accepts it.
  Future<OtpVerifyResult> verifyOtp({
    required OtpChallenge challenge,
    required String code,
  }) async {
    final normalizedCode = code.trim();
    // rider-u73: expiry is the server's call (410 otp_expired); the device
    // clock can run minutes ahead and turned every code down.
    if (!RidePin.isValidFormat(normalizedCode)) {
      throw ArgumentError.value(code, 'code', 'A 4-digit code is required.');
    }
    final response = await _api.post(
      '/api/v1/auth/otp/verify',
      body: {
        'phone': challenge.phone,
        'sessionId': challenge.sessionId,
        'code': normalizedCode,
        if (challenge.link != null) 'linkToken': challenge.link!.linkToken,
      },
    );
    await _persistTokens(response);
    final isNewRider = response['isNewRider'] == true;
    // rider-u74: right after the session exists, so a reload on the name
    // step still asks for the name.
    if (isNewRider) {
      await PendingRiderName.mark(challenge.link?.name);
    } else {
      await PendingRiderName.clear();
    }
    return OtpVerifyResult(isNewRider: isNewRider);
  }

  /// Signs in with Apple or Google.
  ///
  /// The backend either returns tokens (the account already has a verified
  /// phone) or `PHONE_REQUIRED` with a short-lived link token. In the second
  /// case nothing is saved: the session starts only once the phone code is
  /// verified, so a phone number stays mandatory.
  Future<ProviderSignInResult> signIn({required String provider}) async {
    final normalized = provider.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(provider, 'provider', 'Provider is required.');
    }
    final response = await _api.post(
      '/api/v1/auth/provider',
      body: {'provider': normalized},
    );
    if (response['code'] == 'PHONE_REQUIRED') {
      final linkToken = response['linkToken'];
      if (linkToken is! String || linkToken.isEmpty) {
        throw StateError('Phone-required response had no link token.');
      }
      final name = response['name'];
      return ProviderPhoneRequired(
        ProviderLink(
          provider: normalized,
          linkToken: linkToken,
          name: name is String && name.trim().isNotEmpty ? name.trim() : null,
        ),
      );
    }
    await _persistTokens(response);
    return const ProviderSignedIn();
  }

  Future<void> _persistTokens(Map<String, dynamic> response) async {
    final access = response['accessToken'];
    final refresh = response['refreshToken'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw StateError('Authentication response did not contain valid tokens.');
    }
    await _tokens.save(access: access, refresh: refresh);
  }

  Future<String?> readAccessToken() => _tokens.readAccess();

  Future<bool> hasSession() async {
    final access = await _tokens.readAccess();
    final refresh = await _tokens.readRefresh();
    return access?.isNotEmpty == true && refresh?.isNotEmpty == true;
  }

  /// Forgets the session on this device only (the backend already ended it,
  /// e.g. after an account deletion request).
  Future<void> clearLocalSession() => _tokens.clear();

  Future<void> signOut() async {
    try {
      await _api.post('/api/v1/auth/sign-out');
    } finally {
      await _tokens.clear();
    }
  }
}
