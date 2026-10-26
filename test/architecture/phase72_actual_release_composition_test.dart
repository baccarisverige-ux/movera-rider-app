import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/core/notifications/firebase_push_service.dart';
import 'package:movera_rider/core/notifications/push_service.dart';
import 'package:movera_rider/core/observability/observability.dart';
import 'package:movera_rider/core/payments/api_payment_gateway.dart';
import 'package:movera_rider/core/payments/mock_payment_gateway.dart';
import 'package:movera_rider/core/realtime/mock_ride_realtime.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Observability.reset);

  test('compile-time release env parser distinguishes demo and production', () {
    expect(AppEnv.parseFlavor('demo'), AppFlavor.demo);
    expect(AppEnv.parseFlavor('production'), AppFlavor.production);
  });

  test(
    'actual production AppScope composition contains no mock/no-op surfaces',
    () async {
      const production = AppEnv(
        flavor: AppFlavor.production,
        apiBaseUrl: 'https://api.movera.example',
      );

      final scope = AppScope.composeForEnvironment(production);
      addTearDown(scope.disposeForTest);

      expect(scope.environment.flavor, AppFlavor.production);
      expect(scope.api.usesMockTransport, isFalse);
      expect(scope.rideRealtime, isNot(isA<MockRideRealtime>()));
      expect(scope.paymentGateway, isA<ApiPaymentGateway>());
      expect(scope.push, isA<FirebasePushService>());
      expect(scope.emergencyDialer, isNot(isA<RecordingEmergencyDialer>()));
      expect(Observability.logger, isNot(isA<NoopLoggerSink>()));
      expect(Observability.analytics, isNot(isA<NoopAnalyticsSink>()));
      expect(Observability.crashes, isNot(isA<NoopCrashSink>()));
      // ARCH-6 / ARCH-7: no device-only rider repository either.
      for (final repository in <Object>[
        scope.walletBalances,
        scope.reservationRepository,
        scope.savedCardsStore,
      ]) {
        expect(repository, isA<FeatureOffRepository>());
      }
      for (final repository in <Object>[
        scope.payments,
        scope.defaultPayment,
        scope.rideHistory,
        scope.activeTrips,
        scope.profile.repository,
      ]) {
        expect(repository, isA<ServerBackedRepository>());
      }
    },
  );

  test('demo AppScope is explicitly allowed to use mock transports', () {
    const demo = AppEnv(
      flavor: AppFlavor.demo,
      apiBaseUrl: 'https://api.demo.movera.invalid',
    );

    final scope = AppScope.composeForEnvironment(demo);
    addTearDown(scope.disposeForTest);

    expect(scope.environment.flavor, AppFlavor.demo);
    expect(scope.api.usesMockTransport, isTrue);
    expect(scope.rideRealtime, isA<MockRideRealtime>());
    expect(scope.paymentGateway, isA<MockPaymentGateway>());
    expect(scope.push, isA<NoopPushService>());
  });
}
