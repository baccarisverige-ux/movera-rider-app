/// v0.18.38 §62 (fix job 8): the trip stream hands each in-app call event
/// (`call_*`, with its `call` or `signal` payload) to whoever listens — the
/// calls hub (features/calls), wired in di.dart. Core knows no feature.
class RideCallEvents {
  RideCallEvents._();

  static void Function(
    String tripId,
    String kind,
    Map<String, dynamic> payload,
  )?
  sink;
}
