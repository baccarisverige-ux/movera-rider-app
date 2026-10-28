class AccountSecurityCapabilities {
  const AccountSecurityCapabilities({
    this.passkeys = false,
    this.password = false,
    this.authenticator = false,
    this.twoStep = false,
    this.recoveryPhone = false,
    this.connectedAccounts = false,
    this.reauthentication = false,
    this.signOutOtherDevices = false,
  });

  final bool passkeys;
  final bool password;
  final bool authenticator;
  final bool twoStep;
  final bool recoveryPhone;
  final bool connectedAccounts;
  final bool reauthentication;
  final bool signOutOtherDevices;

  factory AccountSecurityCapabilities.fromJson(Map<String, dynamic> json) {
    return AccountSecurityCapabilities(
      passkeys: json['passkeys'] == true,
      password: json['password'] == true,
      authenticator: json['authenticator'] == true,
      twoStep: json['twoStep'] == true,
      recoveryPhone: json['recoveryPhone'] == true,
      connectedAccounts: json['connectedAccounts'] == true,
      reauthentication: json['reauthentication'] == true,
      signOutOtherDevices: json['signOutOtherDevices'] == true,
    );
  }
}

class AccountSession {
  const AccountSession({
    required this.id,
    required this.device,
    required this.place,
    required this.source,
    required this.current,
  });

  final String id;
  final String device;
  final String place;
  final String source;
  final bool current;

  factory AccountSession.fromJson(Map<String, dynamic> json) {
    return AccountSession(
      id: json['id'] as String? ?? '',
      device: json['device'] as String? ?? '',
      place: json['place'] as String? ?? '',
      source: json['source'] as String? ?? '',
      current: json['current'] == true,
    );
  }
}

class AccountSecurityState {
  const AccountSecurityState({
    required this.phone,
    required this.email,
    required this.phoneVerifiedAt,
    required this.emailVerifiedAt,
    required this.passkeyEnabled,
    required this.twoStepEnabled,
    required this.authenticatorEnabled,
    required this.passwordUpdatedAt,
    required this.recoveryPhone,
    required this.googleConnected,
    required this.appleConnected,
    required this.reauthenticatedAt,
    required this.sessions,
    required this.capabilities,
  });

  final String phone;
  final String email;
  final DateTime? phoneVerifiedAt;
  final DateTime? emailVerifiedAt;
  final bool passkeyEnabled;
  final bool twoStepEnabled;
  final bool authenticatorEnabled;
  final DateTime? passwordUpdatedAt;
  final String? recoveryPhone;
  final bool googleConnected;
  final bool appleConnected;
  final DateTime? reauthenticatedAt;
  final List<AccountSession> sessions;
  final AccountSecurityCapabilities capabilities;

  bool get phoneVerified => phoneVerifiedAt != null;
  bool get emailVerified => emailVerifiedAt != null;
  bool get hasFreshReauthentication {
    final at = reauthenticatedAt;
    if (at == null) return false;
    final age = DateTime.now().toUtc().difference(at);
    return !age.isNegative && age <= const Duration(minutes: 5);
  }

  bool get checkupComplete =>
      phoneVerified && twoStepEnabled && (recoveryPhone ?? '').isNotEmpty;

  factory AccountSecurityState.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toUtc() : null;
    final rawSessions = json['sessions'];
    return AccountSecurityState(
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phoneVerifiedAt: parseDate(json['phoneVerifiedAt']),
      emailVerifiedAt: parseDate(json['emailVerifiedAt']),
      passkeyEnabled: json['passkeyEnabled'] == true,
      twoStepEnabled: json['twoStepEnabled'] == true,
      authenticatorEnabled: json['authenticatorEnabled'] == true,
      passwordUpdatedAt: parseDate(json['passwordUpdatedAt']),
      recoveryPhone: json['recoveryPhone'] as String?,
      googleConnected: json['googleConnected'] == true,
      appleConnected: json['appleConnected'] == true,
      reauthenticatedAt: parseDate(json['reauthenticatedAt']),
      sessions: rawSessions is List
          ? rawSessions
                .whereType<Map>()
                .map(
                  (item) =>
                      AccountSession.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
      capabilities: AccountSecurityCapabilities.fromJson(
        json['capabilities'] is Map
            ? Map<String, dynamic>.from(json['capabilities'] as Map)
            : const {},
      ),
    );
  }
}
