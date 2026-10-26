import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/config/wallet_composition.dart';
import 'package:movera_rider/features/wallet/data/wallet_repository.dart';

void main() {
  const production = AppEnv(
    flavor: AppFlavor.production,
    apiBaseUrl: 'https://api.movera.example',
  );
  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.staging.movera.example',
  );
  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );

  test('WalletStore is the local, non-authoritative balance source', () {
    expect(WalletStore(), isA<WalletBalanceSource>());
  });

  test('staging/production reject a client-local wallet balance', () {
    for (final environment in <AppEnv>[staging, production]) {
      expect(
        () => WalletComposition.validate(
          environment: environment,
          usesLocalBalanceSource: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('wallet balance'),
          ),
        ),
      );
    }
  });

  test('demo/dev may explicitly use the local wallet balance', () {
    expect(
      () => WalletComposition.validate(
        environment: demo,
        usesLocalBalanceSource: true,
      ),
      returnsNormally,
    );
  });

  test(
    'a real server-backed balance source would pass release composition',
    () {
      expect(
        () => WalletComposition.validate(
          environment: production,
          usesLocalBalanceSource: false,
        ),
        returnsNormally,
      );
    },
  );
}
