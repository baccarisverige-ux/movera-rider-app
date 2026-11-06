import 'package:movera_rider/l10n/l10n.dart';

/// Contract v0.5.1 `TripProjection.searchStep { id, kind, message,
/// extraMin, at }` (rider view, `dispatch.searchStep`): the latest
/// rider-waiting step of the admin's search steps that fired. `keep_waiting`
/// asks Keep waiting / Stop (`POST /trips/{tripId}/keep-waiting`), `busy`
/// says the search ended, `alert_admin` only alerts Movera (its message, if
/// any, is shown as it is).
///
/// v0.18.39 §63 (owner N2, contract.json#noDriverNearby): `no_driver_nearby`
/// is shown once for a live ride with no driver and asks the same Keep
/// waiting / Cancel free; the search goes on. `no_driver_found` (P17) is a
/// booked ride the server ended at pickup + 15 min, no fee. Both show the
/// app's own words in the rider's language (the server text is the admin's
/// fallback).
class TripSearchStep {
  const TripSearchStep({
    required this.id,
    required this.kind,
    required this.message,
    this.extraMin,
  });

  static const kinds = {
    'alert_admin',
    'keep_waiting',
    'busy',
    'no_driver_nearby',
    'no_driver_found',
  };

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
      message: switch (kind) {
        'no_driver_nearby' => L10n.current.searchStepNoDriverNearby,
        'no_driver_found' => L10n.current.searchStepNoDriverFound,
        _ => message is String ? message.trim() : '',
      },
      extraMin: extra is num ? extra.round() : null,
    );
  }

  final String id;

  /// `alert_admin`, `keep_waiting`, `busy`, `no_driver_nearby` or
  /// `no_driver_found`.
  final String kind;

  /// The admin's text for this step (already in the rider's language).
  final String message;

  /// keep_waiting: the minutes "Keep waiting" adds to the search.
  final int? extraMin;

  bool get asksKeepWaiting =>
      kind == 'keep_waiting' || kind == 'no_driver_nearby';
}
