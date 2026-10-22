import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/features/profile/domain/account_security.dart';

class AccountSecurityRepository {
  AccountSecurityRepository({required ApiClient api}) : _api = api;

  final ApiClient _api;

  Future<AccountSecurityState> load() async {
    final response = await _api.get('/api/v1/account/security');
    return _decode(response);
  }

  /// rider-u146: the sign-out answer carries the new `security`, so it is
  /// read from there. A separate GET could fail after the sign-out went
  /// through and report that as a failure (a retry then gets 403
  /// reauth_required). Only an answer without it is read again.
  Future<AccountSecurityState> signOutOtherDevices() async {
    final response = await _api.post(
      '/api/v1/account/security/sessions/sign-out-others',
    );
    if (response['security'] is Map) return _decode(response);
    return load();
  }

  AccountSecurityState _decode(Map<String, dynamic> response) {
    final raw = response['security'];
    if (raw is! Map) {
      throw StateError('Account security response was incomplete.');
    }
    return AccountSecurityState.fromJson(Map<String, dynamic>.from(raw));
  }
}
