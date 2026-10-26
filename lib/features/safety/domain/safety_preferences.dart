enum TripShareMode { auto, manual }

class SafetyPreferences {
  const SafetyPreferences({
    this.userId = 'rider-local',
    this.pinRequired = false,
    this.tripShareEnabled = false,
    this.tripShareMode = TripShareMode.manual,
    this.tripShareContactIds = const [],
    this.rideCheckEnabled = true,
    this.updatedAt,
    this.version = 1,
  });

  final String userId;
  final bool pinRequired;
  final bool tripShareEnabled;
  final TripShareMode tripShareMode;
  final List<String> tripShareContactIds;
  final bool rideCheckEnabled;
  final DateTime? updatedAt;
  final int version;

  SafetyPreferences copyWith({
    String? userId,
    bool? pinRequired,
    bool? tripShareEnabled,
    TripShareMode? tripShareMode,
    List<String>? tripShareContactIds,
    bool? rideCheckEnabled,
    DateTime? updatedAt,
    int? version,
  }) {
    return SafetyPreferences(
      userId: userId ?? this.userId,
      pinRequired: pinRequired ?? this.pinRequired,
      tripShareEnabled: tripShareEnabled ?? this.tripShareEnabled,
      tripShareMode: tripShareMode ?? this.tripShareMode,
      tripShareContactIds: tripShareContactIds ?? this.tripShareContactIds,
      rideCheckEnabled: rideCheckEnabled ?? this.rideCheckEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'pinRequired': pinRequired,
    'tripShareEnabled': tripShareEnabled,
    'tripShareMode': tripShareMode.name,
    'tripShareContactIds': tripShareContactIds,
    'rideCheckEnabled': rideCheckEnabled,
    'updatedAt': updatedAt?.toIso8601String(),
    'version': version,
  };

  factory SafetyPreferences.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SafetyPreferences();
    final mode = '${json['tripShareMode'] ?? 'manual'}';
    final ids = json['tripShareContactIds'];
    return SafetyPreferences(
      userId: json['userId'] as String? ?? 'rider-local',
      pinRequired: json['pinRequired'] == true,
      tripShareEnabled: json['tripShareEnabled'] == true,
      tripShareMode: mode == 'auto' ? TripShareMode.auto : TripShareMode.manual,
      tripShareContactIds: ids is List
          ? ids.map((item) => '$item').toList()
          : const [],
      rideCheckEnabled: json['rideCheckEnabled'] != false,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
      version: json['version'] is int ? json['version'] as int : 1,
    );
  }
}
