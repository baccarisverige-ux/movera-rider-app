enum SafetyKind { shareTrip, sos, maskedCall, ridePin, incident }

class SafetyEvent {
  const SafetyEvent({
    required this.kind,
    required this.at,
    this.rideId,
    this.id,
  });

  final SafetyKind kind;
  final DateTime at;
  final String? rideId;
  final String? id;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'at': at.toIso8601String(),
    if (rideId != null) 'rideId': rideId,
    if (id != null) 'id': id,
  };

  factory SafetyEvent.fromJson(Map<String, dynamic> json) {
    return SafetyEvent(
      kind: SafetyKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => SafetyKind.incident,
      ),
      at:
          DateTime.tryParse('${json['at']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      rideId: json['rideId'] as String?,
      id: json['id'] as String?,
    );
  }
}
