import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/config/transport_composition.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/core/payments/mock_payment_gateway.dart';
import 'package:movera_rider/core/payments/unavailable_payment_gateway.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';

void main() {
  const production = AppEnv(
    flavor: AppFlavor.production,
    apiBaseUrl: 'https://api.movera.example',
  );
  const dev = AppEnv(
    flavor: AppFlavor.dev,
    apiBaseUrl: 'https://api.dev.movera.invalid',
  );
  const testEnv = AppEnv(
    flavor: AppFlavor.test,
    apiBaseUrl: 'https://api.test.movera.invalid',
  );
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );

  test('production ApiClient never silently chooses in-process mock', () {
    final api = ApiClient(env: production);
    expect(api.usesMockTransport, isFalse);
  });

  test('dev/test may explicitly use in-process transport', () {
    for (final environment in <AppEnv>[dev, testEnv]) {
      final api = ApiClient(env: environment, client: InProcessMockClient());
      expect(api.usesMockTransport, isTrue);
    }
  });

  test('staging/production composition rejects mock realtime/payment/push', () {
    for (final environment in <AppEnv>[staging, production]) {
      final api = ApiClient(env: environment);
      final realtime = MockRideRealtime(api: api);

      expect(
        () => TransportComposition.validate(
          environment: environment,
          api: api,
          realtime: realtime,
          paymentGateway: MockPaymentGateway(),
          push: NoopPushService(),
          emergencyDialer: RecordingEmergencyDialer(),
          logger: const NoopLoggerSink(),
          analytics: const NoopAnalyticsSink(),
          crashes: const NoopCrashSink(),
        ),
        throwsStateError,
      );

      realtime.dispose();
    }
  });

  test('release rejection identifies a recording emergency dialer', () {
    final api = ApiClient(env: production);
    final realtime = MockRideRealtime(api: api);

    expect(
      () => TransportComposition.validate(
        environment: production,
        api: api,
        realtime: realtime,
        paymentGateway: MockPaymentGateway(),
        push: NoopPushService(),
        emergencyDialer: RecordingEmergencyDialer(),
        logger: const NoopLoggerSink(),
        analytics: const NoopAnalyticsSink(),
        crashes: const NoopCrashSink(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('emergencyDialer'),
        ),
      ),
    );

    realtime.dispose();
  });

  test('release composition rejects noop observability sinks', () {
    final api = ApiClient(env: production);
    final realtime = MockRideRealtime(api: api);

    expect(
      () => TransportComposition.validate(
        environment: production,
        api: api,
        realtime: realtime,
        paymentGateway: MockPaymentGateway(),
        push: NoopPushService(),
        emergencyDialer: SystemEmergencyDialer(launcher: (_) async => true),
        logger: const NoopLoggerSink(),
        analytics: const NoopAnalyticsSink(),
        crashes: const NoopCrashSink(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('logger'), contains('analytics'), contains('crashes')),
        ),
      ),
    );

    realtime.dispose();
  });

  test('dev composition accepts mock stack', () {
    final api = ApiClient(env: dev, client: InProcessMockClient());
    final realtime = MockRideRealtime(api: api);

    expect(
      () => TransportComposition.validate(
        environment: dev,
        api: api,
        realtime: realtime,
        paymentGateway: MockPaymentGateway(),
        push: NoopPushService(),
        emergencyDialer: RecordingEmergencyDialer(),
        logger: const NoopLoggerSink(),
        analytics: const NoopAnalyticsSink(),
        crashes: const NoopCrashSink(),
      ),
      returnsNormally,
    );

    realtime.dispose();
  });

  test('release composition rejects unavailable payment placeholder', () {
    final api = ApiClient(env: production);
    final realtime = MockRideRealtime(api: api);

    expect(
      () => TransportComposition.validate(
        environment: production,
        api: api,
        realtime: realtime,
        paymentGateway: const UnavailablePaymentGateway(),
        push: NoopPushService(),
        emergencyDialer: RecordingEmergencyDialer(),
        logger: const NoopLoggerSink(),
        analytics: const NoopAnalyticsSink(),
        crashes: const NoopCrashSink(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('payments'),
        ),
      ),
    );

    realtime.dispose();
  });

  test('release composition rejects unavailable push placeholder', () {
    final api = ApiClient(env: production);
    final realtime = MockRideRealtime(api: api);

    expect(
      () => TransportComposition.validate(
        environment: production,
        api: api,
        realtime: realtime,
        paymentGateway: MockPaymentGateway(),
        push: const UnavailablePushService(),
        emergencyDialer: RecordingEmergencyDialer(),
        logger: const NoopLoggerSink(),
        analytics: const NoopAnalyticsSink(),
        crashes: const NoopCrashSink(),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('push'),
        ),
      ),
    );

    realtime.dispose();
  });
}
