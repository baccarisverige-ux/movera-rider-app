class RidePin {
  const RidePin({
    required this.pinId,
    required this.userId,
    required this.pin,
    this.requiredForStart = false,
    this.rotatedAt,
    this.version = 1,
    this.serverAuthoritative = false,
  });

  final String pinId;
  final String userId;

  /// Rider-facing digits; empty when the server did not issue a valid PIN.
  final String pin;
  final bool requiredForStart;
  final DateTime? rotatedAt;
  final int version;
  final bool serverAuthoritative;
  bool get isAvailable => isValidFormat(pin);

  static const unavailable = RidePin(pinId: '', userId: '', pin: '');

  /// Whether [value] is a well-formed 4-digit ride PIN. The single source of
  /// truth for this shape, reused anywhere a raw PIN string is validated.
  static bool isValidFormat(String value) => RegExp(r'^\d{4}$').hasMatch(value);

  RidePin copyWith({
    String? pinId,
    String? userId,
    String? pin,
    bool? requiredForStart,
    DateTime? rotatedAt,
    int? version,
    bool? serverAuthoritative,
  }) {
    return RidePin(
      pinId: pinId ?? this.pinId,
      userId: userId ?? this.userId,
      pin: pin ?? this.pin,
      requiredForStart: requiredForStart ?? this.requiredForStart,
      rotatedAt: rotatedAt ?? this.rotatedAt,
      version: version ?? this.version,
      serverAuthoritative: serverAuthoritative ?? this.serverAuthoritative,
    );
  }

  Map<String, dynamic> toJson() => {
    'pinId': pinId,
    'userId': userId,
    'pin': pin,
    'required': requiredForStart,
    'rotatedAt': rotatedAt?.toIso8601String(),
    'version': version,
    'serverAuthoritative': serverAuthoritative,
  };

  factory RidePin.fromJson(Map<String, dynamic>? json) {
    if (json == null) return unavailable;
    final raw = '${json['pin'] ?? ''}';
    final pin = isValidFormat(raw) ? raw : '';
    return RidePin(
      pinId: json['pinId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      pin: pin,
      requiredForStart:
          json['required'] == true || json['requiredForStart'] == true,
      rotatedAt: DateTime.tryParse('${json['rotatedAt'] ?? ''}'),
      version: json['version'] is int ? json['version'] as int : 1,
      serverAuthoritative:
          json['serverAuthoritative'] == true && pin.isNotEmpty,
    );
  }
}
