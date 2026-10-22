class AppNotification {
  const AppNotification({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.read,
    this.messageId,
    this.rideId,
    this.deepLink,
    this.at,
  });

  final String kind;
  final String title;
  final String subtitle;
  final String time;
  final bool read;
  final String? messageId;
  final String? rideId;
  final String? deepLink;

  /// When it was sent, local time (FLOW-18); [time] is its label.
  final DateTime? at;

  AppNotification copyWith({bool? read, String? time}) {
    return AppNotification(
      kind: kind,
      title: title,
      subtitle: subtitle,
      time: time ?? this.time,
      read: read ?? this.read,
      messageId: messageId,
      rideId: rideId,
      deepLink: deepLink,
      at: at,
    );
  }
}
