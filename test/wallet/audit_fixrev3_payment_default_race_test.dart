// rider-fixrev3-5: in release the Payments tab's default comes from a server
// GET (up to 2x15 s). A method tapped before it answers is saved correctly,
// but the late answer used to re-mark the previous server default on the
// tile and in ApiPaymentMethodRepository's cached id, and a Personal/Business
// tap in that window re-saved the not yet loaded default (Cash).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/payments/data/api_payment_method_repository.dart';
import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/wallet/application/wallet_controller.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A slow network: the GET answer is computed at once and delivered when
/// the test says so.
class _SlowPaymentServer extends InProcessMockClient {
  final List<Completer<void>> _held = [];
  final List<String> patched = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path == ApiPaymentMethodRepository.path && request.method == 'GET') {
      final response = await super.send(request);
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
      return response;
    }
    if (path == '${ApiPaymentMethodRepository.path}/default') {
      patched.add((request as http.Request).body);
    }
    return super.send(request);
  }

  void release() {
    for (final gate in _held) {
      if (!gate.isCompleted) gate.complete();
    }
    _held.clear();
  }
}

/// The default store of a release build on a slow network, as the wallet
/// sees it: reads answer when released, saves are recorded.
class _SlowDefaultStore implements DefaultPaymentStore {
  _SlowDefaultStore(this.serverValue);

  String serverValue;
  final List<String> saves = [];
  final List<Completer<void>> _held = [];

  @override
  Future<String?> read() async {
    // The answer is what the server held when the request arrived.
    final answer = serverValue;
    final gate = Completer<void>();
    _held.add(gate);
    await gate.future;
    return answer;
  }

  @override
  Future<void> save(String brand) async {
    saves.add(brand);
    serverValue = brand;
  }

  void release() {
    for (final gate in _held) {
      if (!gate.isCompleted) gate.complete();
    }
    _held.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const demo = AppEnv(
    flavor: AppFlavor.demo,
    apiBaseUrl: 'https://api.demo.movera.invalid',
  );

  test('a default saved during a read is not undone by its answer', () async {
    final server = _SlowPaymentServer()..defaultPaymentMethodId = 'google';
    final repo = ApiPaymentMethodRepository(
      api: ApiClient(client: server, env: demo),
    );
    final slowRead = repo.read();
    await Future<void>.delayed(Duration.zero);
    await repo.save('apple');
    expect(server.patched, ['{"methodId":"apple"}']);

    server.release();
    expect(await slowRead, 'apple', reason: 'the stale answer is ignored');
    // The network is gone: the last known choice stands.
    server.failNext = true;
    final offline = repo.read();
    await Future<void>.delayed(Duration.zero);
    server.release();
    expect(await offline, 'apple');
  });

  Finder tile(String id) => find.byKey(ValueKey('wallet-method-$id'));
  Finder defaultOn(String id) =>
      find.descendant(of: tile(id), matching: find.text('Default for rides'));

  testWidgets('a method tapped before the default loads stays marked', (
    tester,
  ) async {
    // G8: no Google Pay; Apple Pay (iPhone) is the other method here.
    final store = _SlowDefaultStore('cash');
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(wallet: WalletController(defaultPayment: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(defaultOn('cash'), findsOneWidget, reason: 'nothing loaded yet');

    await tester.tap(tile('apple'));
    await tester.pumpAndSettle();
    expect(store.saves, ['apple']);
    expect(defaultOn('apple'), findsOneWidget);

    // The server's old answer lands after the tap.
    store.release();
    await tester.pumpAndSettle();
    expect(defaultOn('apple'), findsOneWidget);
    expect(defaultOn('cash'), findsNothing);
    expect(store.saves, ['apple']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('the Business toggle does not re-save the default method', (
    tester,
  ) async {
    final store = _SlowDefaultStore('apple');
    await tester.pumpWidget(
      MaterialApp(
        home: WalletScreen(
          wallet: WalletController(defaultPayment: store),
          flags: const FeatureFlags(enableBusinessProfile: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Business'));
    await tester.pumpAndSettle();
    expect(store.saves, isEmpty, reason: 'only the business flag is saved');
    expect(store.serverValue, 'apple');

    store.release();
    await tester.pumpAndSettle();
    expect(defaultOn('apple'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('movera_payment_business'), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
