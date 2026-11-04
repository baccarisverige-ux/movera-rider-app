import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/features/wallet/data/api_wallet_repository.dart';

/// Movera fix job 6 (ledger L11/R11, owner Q4 2026-11-04): the wallet keeps
/// one balance per currency; a France refund is euro, never kronor.
void main() {
  final asked = <String>[];
  ApiWalletRepository repo(String currency) => ApiWalletRepository(
    currency: currency,
    api: ApiClient(
      env: const AppEnv(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://x.invalid',
      ),
      client: MockClient((request) async {
        final wanted = request.url.queryParameters['currency'] ?? 'SEK';
        asked.add(wanted);
        const balances = [
          {'amountMinor': 6500, 'currency': 'EUR'},
          {'amountMinor': 3000, 'currency': 'SEK'},
        ];
        final balance = balances.firstWhere(
          (b) => b['currency'] == wanted,
          orElse: () => {'amountMinor': 0, 'currency': wanted},
        );
        return http.Response(
          jsonEncode({
            'ownerId': 'rdr_1',
            'balance': balance,
            'balances': balances,
            'updatedAt': '2026-11-04T10:00:00Z',
          }),
          200,
        );
      }),
    ),
  );

  setUp(asked.clear);

  test('each currency reads its own balance from the server', () async {
    expect(await repo('EUR').loadBalance(), 65.0);
    expect(await repo('SEK').loadBalance(), 30.0);
    expect(await repo('TND').loadMoney(), const Money(0, 'TND'));
    expect(asked, ['EUR', 'SEK', 'TND']);
  });

  test('balances are listed per currency, never added together', () async {
    expect(await repo('SEK').loadBalances(), const [
      Money(6500, 'EUR'),
      Money(3000, 'SEK'),
    ]);
  });

  test('inCurrency switches the balance; movements re-read the server '
      '(the device never changes money)', () async {
    final eur = repo('SEK').inCurrency('EUR');
    expect(eur.currency, 'EUR');
    expect(
      await eur.debitRide(rideId: 't1', previous: 999, amount: 10),
      65.0,
    );
    expect(await eur.refund(previous: 0, amount: 5), 65.0);
    expect(eur, isA<ServerBackedRepository>());
  });

  test('an older server with only balance still gives one balance', () {
    expect(
      ApiWalletRepository.balancesOf({
        'balance': {'amountMinor': 1200, 'currency': 'SEK'},
      }),
      const [Money(1200, 'SEK')],
    );
  });
}
