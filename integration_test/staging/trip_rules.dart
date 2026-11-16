/// Plain rules of the rider trip run (FTL-H1, FTL-H3; Rules
/// audits/impact/firebase-trip-run-2026-11-16.md rows 1 and 4). No Flutter:
/// unit tested in test/device_suite/ftl_harness_test.dart.
library;

/// The server's arrive distance when the trip's terms do not say
/// (contract.json autoArrive.settings.arriveMeters.default).
const int defaultAutoArriveMeters = 100;

/// FTL-H1: the driver stops at least this far from the pickup before
/// SWITCH-1, so the server cannot auto-arrive during the background/resume.
const double minStopShortMeters = 150;

/// The trip's arrive distance (`terms.autoArriveMeters`), else the default.
int autoArriveMetersOf(Object? view) {
  final terms = view is Map ? view['terms'] : null;
  final m = terms is Map ? terms['autoArriveMeters'] : null;
  return m is num && m > 0 ? m.round() : defaultAutoArriveMeters;
}

/// How far short of the pickup the driver stops on the way: the trip's
/// arrive distance + 50 m, and never under [minStopShortMeters].
double stopShortMeters(Object? view) {
  final m = autoArriveMetersOf(view) + 50.0;
  return m < minStopShortMeters ? minStopShortMeters : m;
}

/// SWITCH-n: the server status may stay the same, or move forward on its
/// own while the app is in the background: the server auto-arrives when
/// the driver's fixes come within the arrive distance (server
/// src/trips/ride/geofence.ts). Anything else is a FAIL.
bool switchStatusKept(String? before, String? after) {
  if (before == null || after == null) return false;
  if (before == after) return true;
  return after == 'arrived' &&
      (before == 'driver_to_pickup' || before == 'accepted');
}

/// SWITCH-n: the trip is still what the rider sees: the trip screen is the
/// top route, or the app's own "Driver arrived" sheet is over it AND the
/// server says `arrived` (the right screen after an auto-arrive). The
/// sheet at any other status, or any other route on top, is a FAIL: a
/// lost trip screen can never pass.
bool tripKept({
  required bool tripOnTop,
  required bool arrivedSheetOnTop,
  required String? statusAfter,
}) => tripOnTop || (arrivedSheetOnTop && statusAfter == 'arrived');

/// ARRIVED: send `arrive` only when the trip is not yet `arrived`.
bool arriveNeeded(String? status) => status != 'arrived';

/// ARRIVED: the driver's arrive answer is fine when it is 2xx, or a 409
/// while the server already says `arrived` (auto-arrive won the race).
bool arriveAnswerOk(int status, String? statusAfter) =>
    (status >= 200 && status < 300) ||
    (status == 409 && statusAfter == 'arrived');

/// FTL-H3: the rider's ride check reached the server: the server's own
/// check shows the rider's answer, or the app's POST of its own check
/// (any trigger) was taken (2xx) after the card first showed.
bool rideCheckAnswered({
  required Object? serverRideCheck,
  required Iterable<Object?> postsSinceCard,
}) {
  final answers = serverRideCheck is Map ? serverRideCheck['answers'] : null;
  if (answers is Map && answers['rider'] != null) return true;
  return postsSinceCard.any((s) => s is int && s >= 200 && s < 300);
}
