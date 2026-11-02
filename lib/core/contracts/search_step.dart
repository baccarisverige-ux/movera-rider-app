/// Contract v0.5.1 `TripProjection.searchStep { id, kind, message,
/// extraMin, at }` (rider view, `dispatch.searchStep`): the latest
/// rider-waiting step of the admin's search steps that fired. `keep_waiting`
/// asks Keep waiting / Stop (`POST /trips/{tripId}/keep-waiting`), `busy`
/// says the search ended, `alert_admin` only alerts Movera (its message, if
/// any, is shown as it is).
class TripSearchStep {
  const TripSearchStep({
    required this.id,
    required this.kind,
    required this.message,
    this.extraMin,
  });

  static const kinds = {'alert_admin', 'keep_waiting', 'busy'};

  static TripSearchStep? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final kind = raw['kind'];
    final message = raw['message'];
    if (id is! String || id.isEmpty || !kinds.contains(kind)) return null;
    final extra = raw['extraMin'];
    return TripSearchStep(
      id: id,
      kind: kind as String,
      message: message is String ? message.trim() : '',
      extraMin: extra is num ? extra.round() : null,
    );
  }

  final String id;

  /// `alert_admin`, `keep_waiting` or `busy`.
  final String kind;

  /// The admin's text for this step (already in the rider's language).
  final String message;

  /// keep_waiting: the minutes "Keep waiting" adds to the search.
  final int? extraMin;

  bool get asksKeepWaiting => kind == 'keep_waiting';
}
