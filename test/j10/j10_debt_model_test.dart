import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/demo_features.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/data/api_wallet_repository.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// J10 (contract v0.18.84 `debtModel`, owner Q-M1 / Q-M2 / Q-S5-3..5,
/// decisions/session-2026-11-06.md:1098-1102, 1173-1176, 1244-1247): the
/// rider app's part of the debt model. A rider's unpaid fee is a negative
/// wallet balance; it is never added into a price and is paid once; the
/// phone shows only the server's numbers.
///
/// Written to fail first on the app before J10 (origin/main 900a6890):
/// no X-Contract-Version (so no `walletDebt`), the debt added into the
/// list price, the wallet switch could be turned off while owing, a
/// negative balance read "−35,00 kr" and the 409 read as "refused".
Map<String, dynamic> get _contract =>
    jsonDecode(File('contracts/contract.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> get _texts =>
    (_contract['debtModel'] as Map)['texts'] as Map<String, dynamic>;

const _env = AppEnv(
  flavor: AppFlavor.staging,
  apiBaseUrl: 'https://api.movera.test',
);

Map<String, dynamic> _quoteAnswer({Object? walletDebt}) => {
  'quotes': [
    {
      'quoteId': 'qte_j10',
      'categoryId': 'economy',
      'total': {'amountMinor': 12900, 'currency': 'SEK'},
      'fareLines': [
        {
          'code': 'base',
          'amount': {'amountMinor': 12900, 'currency': 'SEK'},
        },
      ],
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'pickup': {'address': 'Västberga', 'lat': 59.295, 'lng': 18.006},
      'dropoff': {'address': 'Hornstull', 'lat': 59.3157, 'lng': 18.034},
      'stops': <Object>[],
      'surgeMultiplier': 1,
      'pickupAt': null,
      'walletDebt': ?walletDebt,
    },
  ],
  'zoneId': 'Z001',
  'serverTime': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RiderOutstanding.reset();
  });
  tearDown(RiderOutstanding.reset);

  test('POST /quotes sends X-Contract-Version, the copy\'s version (the '
      'server sends walletDebt only to 0.18.84 or later)', () async {
    final sent = <http.BaseRequest>[];
    final api = ApiClient(
      env: _env,
      client: MockClient((request) async {
        sent.add(request);
        return http.Response(
          jsonEncode(_quoteAnswer()),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await ApiQuoteRepository(api: api).quote(
      rideType: 'economy',
      distanceMeters: 3000,
      pickup: 'Västberga',
      destination: 'Hornstull',
      pickupPoint: const GeoPoint(59.295, 18.006),
      destinationPoint: const GeoPoint(59.3157, 18.034),
    );
    final version = sent.single.headers['X-Contract-Version'];
    expect(version, _contract['version']);
    final parts = version!.split('.').map(int.parse).toList();
    expect(parts[1] > 18 || (parts[1] == 18 && parts[2] >= 84), isTrue);
    expect(
      (_contract['debtModel'] as Map)['oldApps'],
      contains('X-Contract-Version is 0.18.84 or higher'),
    );
  });

  test('the debt is never added into the price (Q-M2 read at payment)', () {
    RiderOutstanding.current.value = const RiderOutstanding(
      byCurrency: [Money(14900, 'SEK')],
    );
    final selection = RideSelectionController(currency: 'SEK');
    addTearDown(selection.dispose);
    expect(selection.priceFor('economy', 259), 259);
  });

  test('while the rider owes, "Use wallet balance first" stays on '
      '(walletSwitch: walletFirst false is ignored)', () {
    final selection = RideSelectionController(currency: 'SEK')
      ..walletCurrency = 'SEK'
      ..setWalletBalance(-35);
    addTearDown(selection.dispose);
    selection.useWalletFirst = false;
    expect(selection.useWalletFirst, isTrue);

    final clear = RideSelectionController(currency: 'SEK')
      ..walletCurrency = 'SEK'
      ..setWalletBalance(0);
    addTearDown(clear.dispose);
    clear.useWalletFirst = false;
    expect(clear.useWalletFirst, isFalse, reason: 'zero_keeps_off');
  });

  for (final language in ['en', 'fr', 'sv']) {
    test('[$language] 409 rider_debt_above_max reads the contract text '
        'with the server\'s amount', () {
      L10n.use(language);
      addTearDown(() => L10n.use('en'));
      final error = ApiError(
        code: 'conflict',
        message:
            'Trips paid in the car are paused until your unpaid fees '
            'are paid.',
        statusCode: 409,
        reason: 'rider_debt_above_max',
        details: const ['debt:30000 SEK', 'max:30000 SEK'],
      );
      final want = (_texts['riderDebtAboveMax'] as Map)[language]
          .toString()
          .replaceAll('{amount}', formatMoney(const Money(30000, 'SEK')));
      expect(reservationErrorMessage(error, ReservationAction.book), want);
    });
  }

  testWidgets('a negative balance reads "You owe X" (old app: "−35,00 kr")', (
    tester,
  ) async {
    DemoFeatures.debugOverride = false;
    addTearDown(() => DemoFeatures.debugOverride = null);
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final wallet = WalletController(
      balances: ApiWalletRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.staging,
            apiBaseUrl: 'https://x.invalid',
          ),
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'ownerId': 'rdr_1',
                'balance': {'amountMinor': -3500, 'currency': 'SEK'},
                'balances': [
                  {'amountMinor': -3500, 'currency': 'SEK'},
                ],
                'updatedAt': '2026-11-14T10:00:00Z',
              }),
              200,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WalletHome(wallet: wallet)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('You owe ${formatMoney(const Money(3500, 'SEK'))}'),
      findsOneWidget,
    );
  });
}
