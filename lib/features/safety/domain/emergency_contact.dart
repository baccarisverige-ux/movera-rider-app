const kEmergencyContactRelationships = [
  'Partner',
  'Family',
  'Friend',
  'Colleague',
  'Other',
];

const kMaxEmergencyContacts = 5;

class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.userId,
    required this.name,
    required this.phoneE164,
    this.relationship = 'Other',
    this.isPrimary = false,
    this.shareTrips = false,
    this.isEnabled = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String phoneE164;
  final String relationship;
  final bool isPrimary;
  final bool shareTrips;
  final bool isEnabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  EmergencyContact copyWith({
    String? id,
    String? userId,
    String? name,
    String? phoneE164,
    String? relationship,
    bool? isPrimary,
    bool? shareTrips,
    bool? isEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneE164: phoneE164 ?? this.phoneE164,
      relationship: relationship ?? this.relationship,
      isPrimary: isPrimary ?? this.isPrimary,
      shareTrips: shareTrips ?? this.shareTrips,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'phoneE164': phoneE164,
    'relationship': relationship,
    'isPrimary': isPrimary,
    'shareTrips': shareTrips,
    'isEnabled': isEnabled,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? 'rider-local',
      name: json['name'] as String? ?? '',
      phoneE164: json['phoneE164'] as String? ?? '',
      relationship: json['relationship'] as String? ?? 'Other',
      isPrimary: json['isPrimary'] == true,
      shareTrips: json['shareTrips'] == true,
      isEnabled: json['isEnabled'] != false,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }
}
