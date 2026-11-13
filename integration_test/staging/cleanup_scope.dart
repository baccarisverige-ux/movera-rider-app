/// Which trips the clean-up may close (supervisor 2026-11-13, F1): only
/// trips THIS run created, never one the test rider had before the run.
///
/// Pure (no app, no HTTP) so test/device_suite/cleanup_scope_test.dart pins
/// it; the driver suite's model is `_findLostBooking` (Movera-driver-app
/// #570 trip_run.dart).
library;

/// The ids the clean-up closes, in order.
///
/// * [booked]: trips whose booking answer the run recorded (`POST /trips`
///   2xx with a tripId): always in scope.
/// * [answerLost]: a `POST /trips` of the run got no usable answer (no
///   answer, an error, 5xx): the trip may exist anyway. Then the trips in
///   [openNow] that were NOT in [openBefore] (the rider's open trips read
///   before the run's first booking) are in scope too.
/// * [openBefore] null (the snapshot could not be read) or [openNow] null
///   (not readable now): nothing is added, because a trip from before the
///   run cannot be told apart from a lost one (never cancel what the run
///   did not make). [unknown] then says so for the CLEANUP line.
({List<String> ids, bool unknown}) cleanupScope({
  required List<String> booked,
  required bool answerLost,
  required Set<String>? openBefore,
  required Set<String>? openNow,
}) {
  final ids = <String>[
    for (final id in booked)
      if (id.isNotEmpty) id,
  ];
  if (!answerLost) return (ids: _dedupe(ids), unknown: false);
  if (openBefore == null || openNow == null) {
    return (ids: _dedupe(ids), unknown: true);
  }
  for (final id in openNow) {
    if (!openBefore.contains(id)) ids.add(id);
  }
  return (ids: _dedupe(ids), unknown: false);
}

List<String> _dedupe(List<String> ids) {
  final seen = <String>{};
  return [
    for (final id in ids)
      if (seen.add(id)) id,
  ];
}

/// The trip id of a `POST /trips` answer, or null (no id: the answer is
/// not proof that a trip was made).
String? bookedTripIdOf(Object? answer) {
  if (answer is! Map) return null;
  final id = answer['tripId'];
  return id is String && id.isNotEmpty ? id : null;
}

/// True when a `POST /trips` ended without a usable answer: no status
/// (threw / still waiting), status 0, or a 5xx. A 4xx is a clear "no"
/// (nothing was made).
bool bookingAnswerLost({int? status, String? error, Object? answer}) {
  if (error != null || status == null || status == 0) return true;
  if (status >= 500) return true;
  if (status >= 200 && status < 300) return bookedTripIdOf(answer) == null;
  return false;
}
