import 'package:flutter/foundation.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/constants/app_version.dart' as app_version;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/core/payments/mock_payment_gateway.dart';
import 'package:movera_rider/core/payments/payment_gateway.dart';
import 'package:movera_rider/core/payments/unavailable_payment_gateway.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';

abstract final class TransportComposition {
  /// Why [apiBaseUrl] cannot serve a staging/production build, or null.
  ///
  /// A release built without `--dart-define=MOVERA_API_BASE_URL` falls back to
  /// the demo default `https://api.demo.movera.invalid` (or a `.example`
  /// sample host); every request would
  /// then fail with a DNS error at runtime, so composition refuses it.
  static String? releaseApiBaseUrlProblem(String apiBaseUrl) {
    final value = apiBaseUrl.trim();
    if (value.isEmpty) return 'it is empty';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '"$value" is not an absolute URL';
    }
    if (uri.scheme != 'https') return '"$value" is not https';
    final host = uri.host.toLowerCase();
    if (host == 'invalid' || host.endsWith('.invalid')) {
      return '"$value" uses the reserved .invalid placeholder host';
    }
    // D9 (R11-14): .example is reserved for documentation (RFC 2606) and
    // never a real server either.
    if (host == 'example' || host.endsWith('.example')) {
      return '"$value" uses the reserved .example placeholder host';
    }
    return null;
  }

  static void validate({
    required AppEnv environment,
    required ApiClient api,
    required RideRealtime realtime,
    required PaymentGateway paymentGateway,
    required PushService push,
    required EmergencyDialer emergencyDialer,
    required LoggerSink logger,
    required AnalyticsSink analytics,
    required CrashSink crashes,
    String appVersion = app_version.appVersion,
    bool releaseBuild = kReleaseMode,
  }) {
    if (environment.allowsMockTransport) return;

    // D14 (R11-17): a shipped build reports its version (telemetry, the
    // "Update the app" gate); a release built without the define would
    // report `dev`, so it stops at start instead.
    final version = appVersion.trim();
    if (releaseBuild && (version.isEmpty || version == 'dev')) {
      throw StateError(
        'MOVERA_APP_VERSION is missing for the '
        '${environment.flavor.name} release build',
      );
    }

    final baseUrlProblem = releaseApiBaseUrlProblem(environment.apiBaseUrl);
    if (baseUrlProblem != null) {
      throw StateError(
        'MOVERA_API_BASE_URL is not usable for '
        '${environment.flavor.name}: $baseUrlProblem',
      );
    }

    final mockSurfaces = <String>[
      if (api.usesMockTransport) 'api',
      if (realtime is MockRideRealtime) 'realtime',
      if (paymentGateway is MockPaymentGateway ||
          paymentGateway is UnavailablePaymentGateway)
        'payments',
      if (push is NoopPushService || push is UnavailablePushService) 'push',
      if (emergencyDialer is RecordingEmergencyDialer) 'emergencyDialer',
      if (logger is NoopLoggerSink) 'logger',
      if (analytics is NoopAnalyticsSink) 'analytics',
      if (crashes is NoopCrashSink) 'crashes',
      // Phase 137: a usesMockDriverAssignment check used to live here, but
      // ReservationController defines that flag as exactly
      // environment.allowsMockTransport - the same condition the early
      // return above already guards on - so the branch could never fire by
      // the time this list is built. Removed rather than kept as a
      // tautology; reservation dispatch mocking is still gated by that
      // same environment check at its own call site in di.dart.
    ];

    if (mockSurfaces.isNotEmpty) {
      throw StateError(
        'Mock/no-op transport is forbidden for '
        '${environment.flavor.name}: ${mockSurfaces.join(', ')}',
      );
    }
  }
}
