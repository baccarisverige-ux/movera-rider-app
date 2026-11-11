import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/observability/observability.dart';

abstract final class Analytics {
  static void track(String event, {Map<String, Object?> extra = const {}}) {
    final safe = Observability.sanitize(extra);
    Observability.analytics.track(event, extra: safe);
    // D10 (R10 #10): not also an info log (that sent every event a second
    // time, to /telemetry/logs); the debug console still shows it.
    if (kDebugMode) debugPrint('[movera:analytics] $event $safe');
  }

  static void bookingStarted({String? rideId}) =>
      track('booking_started', extra: {'rideId': rideId});
  static void quoteLoaded({String? rideId}) =>
      track('quote_loaded', extra: {'rideId': rideId});
  static void bookingSubmitted({String? rideId}) =>
      track('booking_submitted', extra: {'rideId': rideId});
  static void driverFound({String? rideId}) =>
      track('driver_found', extra: {'rideId': rideId});
  static void bookingFailed({String? rideId}) =>
      track('booking_failed', extra: {'rideId': rideId});
  static void rideCancelled({String? rideId}) =>
      track('ride_cancelled', extra: {'rideId': rideId});
  static void paymentFailed({String? rideId}) =>
      track('payment_failed', extra: {'rideId': rideId});
}
