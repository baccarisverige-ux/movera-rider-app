import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';

/// The ride the completion screen is describing.
///
/// Completion is the one moment the finished ride is still in hand: the active
/// snapshot is read for History archival and then cleared. Hold it here so the
/// receipt and driver on that screen come from the ride the rider actually
/// took, rather than from repositories that know nothing about it.
///
/// In memory only — History is the durable record, and a completion screen
/// outliving the session it belongs to would be describing nothing.
abstract final class LastCompletedRide {
  static RideSnapshot? _snapshot;
  static Money? _charged;

  static RideSnapshot? get value => _snapshot;

  /// What the server said the rider pays, when known (an ended-early
  /// trip's `fare`, UI-01). Null: only the booked price is known.
  static Money? get charged => _charged;

  static void remember(RideSnapshot? snapshot, {Money? charged}) {
    _snapshot = snapshot;
    _charged = charged;
  }

  static void clear() {
    _snapshot = null;
    _charged = null;
  }
}
