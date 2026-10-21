class LoginSession {
  const LoginSession({
    required this.device,
    required this.place,
    required this.source,
    this.current = false,
  });

  final String device;
  final String place;
  final String source;
  final bool current;

  Map<String, dynamic> toJson() => {
    'device': device,
    'place': place,
    'source': source,
    'current': current,
  };

  static LoginSession fromJson(Map<String, dynamic> map) {
    return LoginSession(
      device: map['device'] as String? ?? 'Device',
      place: map['place'] as String? ?? '',
      source: map['source'] as String? ?? '',
      current: map['current'] == true,
    );
  }
}

class RiderProfileData {
  /// The longest name the profile contract accepts (C-12; the server
  /// answers 422 invalid_profile past it). rider-u78.
  static const maxNameLength = 80;

  const RiderProfileData({
    required this.name,
    required this.email,
    required this.phone,
    required this.gender,
    required this.language,
    required this.photoAsset,
    this.passkeyEnabled = false,
    this.twoStepEnabled = false,
    this.authenticatorEnabled = false,
    required this.passwordUpdatedAt,
    this.recoveryPhone,
    this.googleConnected = false,
    this.appleConnected = false,
    this.rideUpdates = true,
    this.promotions = false,
    this.emailUpdates = true,
    this.logins = const [],
  });

  final String name;
  final String email;
  final String phone;
  final String gender;
  final String language;
  final String photoAsset;
  final bool passkeyEnabled;
  final bool twoStepEnabled;
  final bool authenticatorEnabled;
  final DateTime passwordUpdatedAt;
  final String? recoveryPhone;
  final bool googleConnected;
  final bool appleConnected;
  final bool rideUpdates;
  final bool promotions;
  final bool emailUpdates;
  final List<LoginSession> logins;

  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(' ').first;
  }

  RiderProfileData copyWith({
    String? name,
    String? email,
    String? phone,
    String? gender,
    String? language,
    String? photoAsset,
    bool? passkeyEnabled,
    bool? twoStepEnabled,
    bool? authenticatorEnabled,
    DateTime? passwordUpdatedAt,
    String? recoveryPhone,
    bool? googleConnected,
    bool? appleConnected,
    bool? rideUpdates,
    bool? promotions,
    bool? emailUpdates,
    List<LoginSession>? logins,
    bool clearRecovery = false,
  }) {
    return RiderProfileData(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      gender: gender ?? this.gender,
      language: language ?? this.language,
      photoAsset: photoAsset ?? this.photoAsset,
      passkeyEnabled: passkeyEnabled ?? this.passkeyEnabled,
      twoStepEnabled: twoStepEnabled ?? this.twoStepEnabled,
      authenticatorEnabled: authenticatorEnabled ?? this.authenticatorEnabled,
      passwordUpdatedAt: passwordUpdatedAt ?? this.passwordUpdatedAt,
      recoveryPhone: clearRecovery
          ? null
          : (recoveryPhone ?? this.recoveryPhone),
      googleConnected: googleConnected ?? this.googleConnected,
      appleConnected: appleConnected ?? this.appleConnected,
      rideUpdates: rideUpdates ?? this.rideUpdates,
      promotions: promotions ?? this.promotions,
      emailUpdates: emailUpdates ?? this.emailUpdates,
      logins: logins ?? this.logins,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'phone': phone,
    'gender': gender,
    'language': language,
    'photoAsset': photoAsset,
    'passkeyEnabled': passkeyEnabled,
    'twoStepEnabled': twoStepEnabled,
    'authenticatorEnabled': authenticatorEnabled,
    'passwordUpdatedAt': passwordUpdatedAt.toIso8601String(),
    if (recoveryPhone != null) 'recoveryPhone': recoveryPhone,
    'googleConnected': googleConnected,
    'appleConnected': appleConnected,
    'rideUpdates': rideUpdates,
    'promotions': promotions,
    'emailUpdates': emailUpdates,
    'logins': logins.map((item) => item.toJson()).toList(),
  };

  static RiderProfileData fromJson(Map<String, dynamic> map) {
    final fallback = defaults();
    final loginsRaw = map['logins'];
    return RiderProfileData(
      name: map['name'] as String? ?? fallback.name,
      email: map['email'] as String? ?? fallback.email,
      phone: map['phone'] as String? ?? fallback.phone,
      gender: map['gender'] as String? ?? fallback.gender,
      language: languageCode(map['language'] as String?),
      photoAsset: map['photoAsset'] as String? ?? fallback.photoAsset,
      passkeyEnabled: map['passkeyEnabled'] == true,
      twoStepEnabled: map['twoStepEnabled'] == true,
      authenticatorEnabled: map['authenticatorEnabled'] == true,
      passwordUpdatedAt:
          DateTime.tryParse(map['passwordUpdatedAt'] as String? ?? '') ??
          fallback.passwordUpdatedAt,
      recoveryPhone: map['recoveryPhone'] as String?,
      googleConnected: map['googleConnected'] == true,
      appleConnected: map['appleConnected'] == true,
      rideUpdates: map['rideUpdates'] != false,
      promotions: map['promotions'] == true,
      emailUpdates: map['emailUpdates'] != false,
      logins: loginsRaw is List
          ? loginsRaw
                .whereType<Map>()
                .map(
                  (item) =>
                      LoginSession.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : fallback.logins,
    );
  }

  /// `RiderProfileUpdate.language` is a code (`^[a-z]{2}(-[A-Z]{2})?$`):
  /// English until the rider picks a language.
  static const defaultLanguage = 'en';

  /// [value] as a language code. Profiles saved before round 4 hold the
  /// language's name ('English'); those, and anything else that is not a
  /// code, become the code the server accepts.
  static String languageCode(String? value) {
    final raw = value?.trim() ?? '';
    if (RegExp(r'^[a-z]{2}(-[A-Z]{2})?$').hasMatch(raw)) return raw;
    return switch (raw.toLowerCase()) {
      'français' || 'francais' || 'french' => 'fr',
      'svenska' || 'swedish' => 'sv',
      _ => defaultLanguage,
    };
  }

  static RiderProfileData defaults() {
    return RiderProfileData(
      name: '',
      email: '',
      phone: '',
      gender: '',
      language: defaultLanguage,
      photoAsset: '',
      passwordUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
