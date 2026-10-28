/// A masked call to the other side of the trip (contract v0.13.0 §22,
/// `POST /trips/{tripId}/call`). The app never sees or dials the driver's
/// real number: only the [proxyNumber] the telephony provider bridges.
class TripCall {
  const TripCall({required this.tripId, required this.proxyNumber});

  final String tripId;
  final String proxyNumber;
}

abstract interface class TripCallTransport {
  /// `200 TripCall`; `503 unavailable` (reason `call_unavailable`) while no
  /// provider is set up; `409 invalid_transition` (reason `chat_closed`)
  /// after drop-off. Errors are thrown as `ApiError`.
  Future<TripCall> call(String tripId);
}
