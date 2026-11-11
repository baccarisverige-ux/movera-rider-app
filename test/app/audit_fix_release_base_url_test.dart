import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/config/transport_composition.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/notifications/firebase_push_service.dart';
import 'package:movera_rider/core/observability/http_observability.dart';
import 'package:movera_rider/core/payments/payment_gateway.dart';
import 'package:movera_rider/core/realtime/ride_realtime.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';

class _RealGateway implements PaymentGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RealRealtime implements RideRealtime {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  void validate(AppEnv environment, {String? version, bool? release}) {
    final sink = HttpObservabilitySink(baseUrl: 'https://api.movera.example');
    TransportComposition.validate(
      environment: environment,
      api: ApiClient(env: environment),
      realtime: _RealRealtime(),
      paymentGateway: _RealGateway(),
      push: FirebasePushService(
        api: ApiClient(env: environment),
        environment: environment,
      ),
      emergencyDialer: SystemEmergencyDialer(launcher: (_) async => true),
      logger: sink,
      analytics: sink,
      crashes: sink,
      appVersion: version ?? '1.2.3+4',
      releaseBuild: release ?? true,
    );
  }

  AppEnv env(AppFlavor flavor, String url) =>
      AppEnv(flavor: flavor, apiBaseUrl: url);

  test('ARCH-19 staging/production refuse the .invalid demo default', () {
    for (final flavor in [AppFlavor.staging, AppFlavor.production]) {
      for (final url in [
        'https://api.demo.movera.invalid',
        'https://invalid',
        '',
        '   ',
        'http://api.movera.example',
        'api.movera.example',
        // D9 (R11-14): the reserved .example documentation hosts too.
        'https://api.movera.example',
        'https://example',
        'https://API.Movera.EXAMPLE',
      ]) {
        expect(
          () => validate(env(flavor, url)),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('MOVERA_API_BASE_URL'),
            ),
          ),
          reason: '$flavor "$url"',
        );
      }
    }
  });

  test('a real https host passes the base URL check', () {
    expect(
      TransportComposition.releaseApiBaseUrlProblem('https://api.movera.se'),
      isNull,
    );
    expect(
      () => validate(env(AppFlavor.production, 'https://api.movera.se')),
      returnsNormally,
    );
  });

  test('demo/dev/test keep the .invalid placeholder', () {
    for (final flavor in [AppFlavor.demo, AppFlavor.dev, AppFlavor.test]) {
      expect(
        () => validate(env(flavor, 'https://api.demo.movera.invalid')),
        returnsNormally,
      );
    }
  });

  test('D14 (R11-17): a release build without MOVERA_APP_VERSION stops', () {
    for (final flavor in [AppFlavor.staging, AppFlavor.production]) {
      for (final version in ['dev', '', '  ']) {
        expect(
          () =>
              validate(env(flavor, 'https://api.movera.se'), version: version),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('MOVERA_APP_VERSION'),
            ),
          ),
          reason: '$flavor "$version"',
        );
      }
    }
    // A debug or profile run (flutter run, tests) keeps `dev`.
    expect(
      () => validate(
        env(AppFlavor.production, 'https://api.movera.se'),
        version: 'dev',
        release: false,
      ),
      returnsNormally,
    );
    // Demo builds are not shipped as a release with a version.
    expect(
      () => validate(
        env(AppFlavor.demo, 'https://api.demo.movera.invalid'),
        version: 'dev',
      ),
      returnsNormally,
    );
  });
}
