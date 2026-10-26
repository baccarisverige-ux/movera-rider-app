enum AudioUploadStatus { localOnly, pending, uploaded, failed }

enum AudioEncryptionState { none, pending, local }

class AudioRecording {
  const AudioRecording({
    required this.id,
    this.rideId,
    this.localPath,
    this.durationMs = 0,
    this.createdAt,
    this.endedAt,
    this.uploadStatus = AudioUploadStatus.localOnly,
    this.remoteId,
    this.encryptionState = AudioEncryptionState.local,
    this.deviceOnly = false,
  });

  final String id;
  final String? rideId;
  final String? localPath;
  final int durationMs;
  final DateTime? createdAt;
  final DateTime? endedAt;
  final AudioUploadStatus uploadStatus;
  final String? remoteId;
  final AudioEncryptionState encryptionState;

  /// Ride check recordings (RC5): never sent to or registered with Movera.
  final bool deviceOnly;

  bool get isRecording => endedAt == null && createdAt != null;

  AudioRecording copyWith({
    String? id,
    String? rideId,
    String? localPath,
    int? durationMs,
    DateTime? createdAt,
    DateTime? endedAt,
    AudioUploadStatus? uploadStatus,
    String? remoteId,
    AudioEncryptionState? encryptionState,
    bool? deviceOnly,
  }) {
    return AudioRecording(
      id: id ?? this.id,
      rideId: rideId ?? this.rideId,
      localPath: localPath ?? this.localPath,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      remoteId: remoteId ?? this.remoteId,
      encryptionState: encryptionState ?? this.encryptionState,
      deviceOnly: deviceOnly ?? this.deviceOnly,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'rideId': rideId,
    'localPath': localPath,
    'durationMs': durationMs,
    'createdAt': createdAt?.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'uploadStatus': uploadStatus.name,
    'remoteId': remoteId,
    'encryptionState': encryptionState.name,
    if (deviceOnly) 'deviceOnly': true,
  };

  factory AudioRecording.fromJson(Map<String, dynamic> json) {
    return AudioRecording(
      id: json['id'] as String? ?? '',
      rideId: json['rideId'] as String?,
      localPath: json['localPath'] as String?,
      durationMs: json['durationMs'] is int ? json['durationMs'] as int : 0,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      endedAt: DateTime.tryParse('${json['endedAt'] ?? ''}'),
      uploadStatus: AudioUploadStatus.values.firstWhere(
        (value) => value.name == json['uploadStatus'],
        orElse: () => AudioUploadStatus.localOnly,
      ),
      remoteId: json['remoteId'] as String?,
      encryptionState: AudioEncryptionState.values.firstWhere(
        (value) => value.name == json['encryptionState'],
        orElse: () => AudioEncryptionState.local,
      ),
      deviceOnly: json['deviceOnly'] == true,
    );
  }
}
