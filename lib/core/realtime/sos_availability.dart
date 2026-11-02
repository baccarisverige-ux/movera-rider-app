/// Contract v0.18.10 `TripProjection.sosAvailable` (owner G8 Q4): whether
/// the server takes an SOS for the trip now (a driver is assigned). The
/// safety kit follows it when the server sent it, else its older rule.
abstract final class SosAvailability {
  static final Map<String, bool> _byTrip = {};

  static void record(String tripId, Object? value) {
    if (tripId.trim().isEmpty || value is! bool) return;
    _byTrip[tripId.trim()] = value;
  }

  /// Null when the server has not said for [tripId].
  static bool? forTrip(String? tripId) =>
      tripId == null ? null : _byTrip[tripId.trim()];

  static void resetForTest() => _byTrip.clear();
}
