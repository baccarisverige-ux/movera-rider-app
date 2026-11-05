/// A call to the other side of the trip (`POST /trips/{tripId}/call`).
/// v0.18.38 §62 (fix job 8, owner G15 "In-app calls only"): by default
/// [mode] is `in_app` with a [callId] and the [ice] servers; only a country
/// on a phone company answers `phone` with the masked [proxyNumber]
/// (contract v0.13.0 §22). The app never sees the driver's real number.
class TripCall {
  const TripCall({
    required this.tripId,
    this.proxyNumber,
    this.mode = 'phone',
    this.callId,
    this.ice = const [],
    this.raw = const {},
  });

  final String tripId;
  final String? proxyNumber;

  /// `in_app` or `phone`.
  final String mode;
  final String? callId;
  final List<Map<String, dynamic>> ice;

  /// The server's whole `TripCall`.
  final Map<String, dynamic> raw;

  bool get inApp => mode == 'in_app' && callId != null;

  /// The `TripCall` as the call session reads it.
  Map<String, dynamic> toJson() => raw.isNotEmpty
      ? raw
      : {
          'tripId': tripId,
          'mode': mode,
          if (callId != null) 'callId': callId,
          'ice': {'servers': ice, 'ttlSeconds': 0},
          if (proxyNumber != null) 'proxyNumber': proxyNumber,
        };
}

abstract interface class TripCallTransport {
  /// `200 TripCall`; `409 invalid_transition` (reason `call_window_closed`)
  /// outside the window; `403 calls_off`. Errors are thrown as `ApiError`.
  Future<TripCall> call(String tripId);
}
