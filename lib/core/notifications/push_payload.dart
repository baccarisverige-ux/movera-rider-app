enum PushDestination { ride, support, notifications }

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
      // v0.18.51 §73 (riderTripPushBell): the server's notificationId names
      // the notice first — it is also the bell row of GET /notifications,
      // so a push shown in the app and its server row stay one row. The
      // transport's message id only when the push has none.
      messageId:
          readString('notificationId', 'notification_id') ??
          _clean(messageId) ??
          readString('messageId', 'message_id'),
      sentAt: sentAt,
    );
  }

  /// SUP-1: contract `riderTripPush` (kind trip_update) and
  /// `onTrip.rideCheck.push` (kind ride_check) are ride pushes too: a tap
  /// opens (or keeps) the ride, never the Notifications list.
  ///
  /// v0.18.56 §78 `inAppCalls.push` (Q79): kind call_ringing (data
  /// `{ tripId, callId }`, link movera://trips/{tripId}/call) opens the trip,
  /// whose incoming-call sheet shows while the call still rings.
  static const Set<String> _tripPushKinds = {
    'trip_update',
    'ride_check',
    callRingingKind,
  };

  static const String callRingingKind = 'call_ringing';
  static const String _callSegment = 'call';

  /// A service push that is never a row of the Notifications list (the
  /// contract: not stored in GET /notifications).
  bool get isIncomingCall => type == callRingingKind;

  /// Links that name a ride: movera://ride/{id} (older pushes),
  /// movera://trip/{tripId} (riderTripPush) and
  /// movera-rider://trip/{tripId} (Ride Check push). Contract 0.18.49
  /// (owner Q9): the server now spells every trip link trips/{tripId}
  /// (movera://trips/{tripId}, movera-rider://trips/{tripId}); the app keeps
  /// accepting ride/ and trip/ for pushes still on phones.
  static const Set<String> _rideLinkSchemes = {'movera', 'movera-rider'};
  static const Set<String> _rideLinkHosts = {'ride', 'trip', 'trips'};
  static const String _tripsLinkHost = 'trips';

  /// The receipt push (finish.receipt.resend: kind receipt, deep link
  /// movera-rider://trips/{tripId}/receipt). Its tap opens the trip, whose
  /// ended stage is the receipt.
  static const String _receiptKind = 'receipt';
  static const String _receiptSegment = 'receipt';

  /// Contract v0.18.53 §75 (support.answerPush): an admin's answer to a
  /// ticket is pushed as kind support_reply with the deep link
  /// movera://support/{ticketId} (movera-rider:// accepted too). A tap
  /// opens that ticket; any other link of this kind opens the list.
  static const String _supportReplyKind = 'support_reply';
  static const String _supportLinkHost = 'support';

  static bool _isRideKind(String type) =>
      type.startsWith('ride.') ||
      type.startsWith('trip.') ||
      _tripPushKinds.contains(type);

  bool get isRideEvent => _isRideKind(type);

  String? get routedRideId {
    final direct = _clean(rideId);
    if (isRideEvent && direct != null) return direct;

    final isReceipt = type == _receiptKind;
    final link = _clean(deepLink);
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null ||
        !_rideLinkSchemes.contains(uri.scheme) ||
        !_rideLinkHosts.contains(uri.host)) {
      return null;
    }
    final segments = uri.pathSegments;
    // SUP3-R3: any other kind (the booked-ride pushes reservation_*) opens
    // its trip when its link is the contract's trips/{tripId} (Q9), never
    // the Notifications list.
    if (!isRideEvent && !isReceipt) {
      return uri.host == _tripsLinkHost && segments.length == 1
          ? _clean(segments.single)
          : null;
    }
    // {id}/receipt names the trip's receipt (any trip link host);
    // {id}/call the trip of an incoming call.
    if (segments.length == 2 &&
        (segments.last == _receiptSegment ||
            (!isReceipt && segments.last == _callSegment))) {
      return _clean(segments.first);
    }
    // The receipt kind routes only through its receipt link.
    if (isReceipt || segments.length != 1) return null;
    return _clean(segments.single);
  }

  /// The ticket a support_reply push opens, from its deep link.
  String? get routedTicketId {
    if (type != _supportReplyKind) return null;
    final link = _clean(deepLink);
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null ||
        !_rideLinkSchemes.contains(uri.scheme) ||
        uri.host != _supportLinkHost ||
        uri.pathSegments.length != 1) {
      return null;
    }
    return _clean(uri.pathSegments.single);
  }

  PushDestination get destination {
    if (routedRideId != null) return PushDestination.ride;
    if (routedTicketId != null) return PushDestination.support;
    return PushDestination.notifications;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
