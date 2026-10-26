class TripShare {
  const TripShare({
    required this.shareId,
    required this.rideId,
    required this.userId,
    this.contactIds = const [],
    this.pickup,
    this.destination,
    this.currentLocation,
    this.driver,
    this.vehicle,
    this.eta,
    this.rideStatus,
    this.startedAt,
    this.expiresAt,
    this.shareToken,
    this.isActive = false,
  });

  final String shareId;
  final String rideId;
  final String userId;
  final List<String> contactIds;
  final String? pickup;
  final String? destination;
  final Map<String, dynamic>? currentLocation;
  final String? driver;
  final String? vehicle;
  final String? eta;
  final String? rideStatus;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final String? shareToken;
  final bool isActive;

  bool get expired {
    final end = expiresAt;
    if (end == null) return false;
    return DateTime.now().toUtc().isAfter(end);
  }

  TripShare copyWith({
    String? shareId,
    String? rideId,
    String? userId,
    List<String>? contactIds,
    String? pickup,
    String? destination,
    Map<String, dynamic>? currentLocation,
    String? driver,
    String? vehicle,
    String? eta,
    String? rideStatus,
    DateTime? startedAt,
    DateTime? expiresAt,
    String? shareToken,
    bool? isActive,
  }) {
    return TripShare(
      shareId: shareId ?? this.shareId,
      rideId: rideId ?? this.rideId,
      userId: userId ?? this.userId,
      contactIds: contactIds ?? this.contactIds,
      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      currentLocation: currentLocation ?? this.currentLocation,
      driver: driver ?? this.driver,
      vehicle: vehicle ?? this.vehicle,
      eta: eta ?? this.eta,
      rideStatus: rideStatus ?? this.rideStatus,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      shareToken: shareToken ?? this.shareToken,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
    'shareId': shareId,
    'rideId': rideId,
    'userId': userId,
    'contactIds': contactIds,
    'pickup': pickup,
    'destination': destination,
    'currentLocation': currentLocation,
    'driver': driver,
    'vehicle': vehicle,
    'eta': eta,
    'rideStatus': rideStatus,
    'startedAt': startedAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'shareToken': shareToken,
    'isActive': isActive,
  };

  factory TripShare.fromJson(Map<String, dynamic> json) {
    final ids = json['contactIds'];
    return TripShare(
      shareId: json['shareId'] as String? ?? '',
      rideId: json['rideId'] as String? ?? '',
      userId: json['userId'] as String? ?? 'rider-local',
      contactIds: ids is List ? ids.map((item) => '$item').toList() : const [],
      pickup: json['pickup'] as String?,
      destination: json['destination'] as String?,
      currentLocation: json['currentLocation'] is Map
          ? Map<String, dynamic>.from(json['currentLocation'] as Map)
          : null,
      driver: json['driver'] as String?,
      vehicle: json['vehicle'] as String?,
      eta: json['eta'] as String?,
      rideStatus: json['rideStatus'] as String?,
      startedAt: DateTime.tryParse('${json['startedAt'] ?? ''}'),
      expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}'),
      shareToken: json['shareToken'] as String?,
      isActive: json['isActive'] == true,
    );
  }
}
