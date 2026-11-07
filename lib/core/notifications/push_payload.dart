enum PushDestination { ride, notifications }

class PushPayload {
  const PushPayload({
    required this.type,
    this.rideId,
    this.deepLink,
    this.title,
    this.body,
    this.messageId,
    this.sentAt,
  });

  final String type;
  final String? rideId;
  final String? deepLink;
  final String? title;
  final String? body;
  final String? messageId;
  final DateTime? sentAt;

  factory PushPayload.fromMap(
    Map<String, dynamic> data, {
    String? messageId,
    String? title,
    String? body,
    DateTime? sentAt,
  }) {
    // Contract v0.18.3 (R7): the server's pushes carry the bell notice's
    // `kind` (with notificationId and deepLink) instead of `type`.
    final rawType = data['type'] ?? data['kind'];
    if (rawType is! String || rawType.trim().isEmpty) {
      throw const FormatException('Push payload type is required.');
    }

    String? readString(String camel, String snake) {
      final value = data[camel] ?? data[snake];
      if (value is! String || value.trim().isEmpty) return null;
      return value.trim();
    }

    final type = rawType.trim();
    return PushPayload(
      type: type,
      // SUP-1: the contract's trip pushes (riderTripPush, the Ride Check
      // push) carry the trip as `tripId`, not `rideId`.
      rideId:
          readString('rideId', 'ride_id') ??
          (_isRideKind(type) ? readString('tripId', 'trip_id') : null),
      deepLink: readString('deepLink', 'deep_link'),
      title: _clean(title) ?? readString('title', 'title'),
      body: _clean(body) ?? readString('body', 'body'),
      messageId:
          _clean(messageId) ??
          readString('messageId', 'message_id') ??
          readString('notificationId', 'notification_id'),
      sentAt: sentAt,
    );
  }

  /// SUP-1: contract `riderTripPush` (kind trip_update) and
  /// `onTrip.rideCheck.push` (kind ride_check) are ride pushes too: a tap
  /// opens (or keeps) the ride, never the Notifications list.
  static const Set<String> _tripPushKinds = {'trip_update', 'ride_check'};

  /// Links that name a ride: movera://ride/{id} (older pushes),
  /// movera://trip/{tripId} (riderTripPush) and
  /// movera-rider://trip/{tripId} (Ride Check push).
  static const Set<String> _rideLinkSchemes = {'movera', 'movera-rider'};
  static const Set<String> _rideLinkHosts = {'ride', 'trip'};

  static bool _isRideKind(String type) =>
      type.startsWith('ride.') ||
      type.startsWith('trip.') ||
      _tripPushKinds.contains(type);

  bool get isRideEvent => _isRideKind(type);

  String? get routedRideId {
    final direct = _clean(rideId);
    if (isRideEvent && direct != null) return direct;

    if (!isRideEvent) return null;
    final link = _clean(deepLink);
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null ||
        !_rideLinkSchemes.contains(uri.scheme) ||
        !_rideLinkHosts.contains(uri.host)) {
      return null;
    }
    if (uri.pathSegments.length != 1) return null;
    return _clean(uri.pathSegments.single);
  }

  PushDestination get destination => routedRideId == null
      ? PushDestination.notifications
      : PushDestination.ride;

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
