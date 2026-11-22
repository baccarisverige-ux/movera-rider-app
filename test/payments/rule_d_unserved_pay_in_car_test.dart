import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/api_rider_config_repository.dart';
import 'package:movera_rider/core/config/live_data_only.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/payments/application/card_entry_policy.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/data/saved_cards_store.dart';
import 'package:movera_rider/features/payments/presentation/pay_with_page.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rule D (owner 2026-11-19 "show ONLY pay the driver in the car", 2026-11-22
/// "Only pay in car"): a build that needs sign-in (staging, production: the
/// real app) must never show Apple Pay or Card before the server said which
/// methods the zone takes: not while the zone's settings are still on
/// their way, and not when they could not be read and none are kept.
/// Hidden only: with a served list of all three, all three still show, and
/// the demo build is as before.
///
/// The app has no web switch a test can set; the picker treats the web like
/// any target that is not a phone, so macOS stands for "web" here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const staging = AppEnv(
    flavor: AppFlavor.staging,
    apiBaseUrl: 'https://api.movera.invalid',
  );
  late RiderConfigRepository appConfig;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RiderZones.useSamples();
    ServerFeatures.clear();
    appConfig = AppScope.instance.riderConfig;
  });
  tearDown(() {
    LiveDataOnly.on = false;
    CardEntryPolicy.debugOverride = null;
    debugDefaultTargetPlatformOverride = null;
    RiderZones.useSamples();
    ServerFeatures.clear();
    AppScope.instance.riderConfig = appConfig;
  });

  /// The real app: sign-in required, live data only, no Add card.
  void realApp() {
    LiveDataOnly.on = true;
    CardEntryPolicy.debugOverride = false;
  }

  RideSelectionController picker() {
    final selection = RideSelectionController(
      flags: FeatureFlags.release,
      savedCards: SavedCardsController(store: MemorySavedCardsStore()),
    );
    addTearDown(selection.dispose);
    return selection;
  }

  /// The rows the booking picker lists, greyed "coming soon" ones included.
  List<String> rows(RideSelectionController selection) => [
    for (final item in selection.payments()) item.brand,
    for (final item in selection.comingSoonPayments()) '${item.brand} (soon)',
  ];

  /// What Select Ride does with a zone's document (select_ride.dart).
  void apply(RideSelectionController selection, RiderAppConfig config) {
    selection.setZonePaymentMethods(config.paymentMethods);
    selection.setPaymentOptions(config.paymentOptions);
  }

  /// A server that cannot be reached, and nothing kept on the phone.
  ApiRiderConfigRepository unreachable() => ApiRiderConfigRepository(
    api: ApiClient(
      env: staging,
      client: MockClient((_) async => throw http.ClientException('offline')),
    ),
    cache: MemoryRiderConfigCache(),
  );

  Future<void> pumpPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  Future<void> pumpPicker(
    WidgetTester tester,
    RideSelectionController selection,
  ) => pumpPhone(
    tester,
    PayWithPage(
      methods: [
        for (final item in selection.payments())
          PayWithMethod(
            brand: item.brand,
            name: item.name,
            detail: item.detail,
          ),
        for (final item in selection.comingSoonPayments())
          PayWithMethod(
            brand: item.brand,
            name: item.name,
            detail: item.detail,
            comingSoon: true,
          ),
      ],
      selectedBrand: selection.selectedPaymentItem()?.brand,
      walletBalance: 0,
      promotion: null,
      brandMark: (_) => const SizedBox(width: 42, height: 38),
    ),
  );

  group('1. booking picker before the zone settings arrived (real app)', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      final name = platform == TargetPlatform.iOS ? 'iPhone' : 'web';
      testWidgets('$name: only pay in car', (tester) async {
        realApp();
        debugDefaultTargetPlatformOverride = platform;
        final selection = picker();

        expect(rows(selection), ['cash']);
        expect(selection.selectedPaymentItem()?.brand, 'cash');

        await pumpPicker(tester, selection);
        expect(find.byKey(const ValueKey('pay-with-cash')), findsOneWidget);
        expect(find.text('Apple Pay'), findsNothing);
        expect(find.byKey(const ValueKey('pay-with-apple')), findsNothing);
        expect(find.byKey(const ValueKey('pay-with-cards')), findsNothing);
        expect(find.byKey(const ValueKey('pay-with-add')), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('2. Payments tab before the zone settings arrived (real app)', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      final name = platform == TargetPlatform.iOS ? 'iPhone' : 'web';
      testWidgets('$name: only pay in car', (tester) async {
        realApp();
        debugDefaultTargetPlatformOverride = platform;
        // The zone's settings never answer while the tab is open.
        AppScope.instance.riderConfig = _NeverAnswers();

        await pumpPhone(
          tester,
          const WalletScreen(flags: FeatureFlags.release),
        );
        expect(find.text('Pay in car'), findsOneWidget);
        expect(find.text('Apple Pay'), findsNothing);
        expect(find.text('Card'), findsNothing);
        expect(find.text('Add card'), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('3. settings could not be read and none are kept (real app)', () {
    test('the stand-in document offers pay in car only', () async {
      realApp();
      final repo = unreachable();
      addTearDown(repo.dispose);

      final config = await repo.forZone(RiderZones.home.id);
      expect(repo.isServerDocument(config), isFalse);
      expect(config.paymentMethods, ['cash']);
      expect(config.paymentStatus('cash'), 'available');
      expect(config.paymentStatus('card'), isNull);
      expect(config.paymentStatus('apple_pay'), isNull);
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      final name = platform == TargetPlatform.iOS ? 'iPhone' : 'web';
      testWidgets('$name: picker and Payments tab show only pay in car', (
        tester,
      ) async {
        realApp();
        debugDefaultTargetPlatformOverride = platform;
        final repo = unreachable();
        final config = (await tester.runAsync(
          () => repo.forZone(RiderZones.home.id),
        ))!;
        repo.dispose();

        final selection = picker();
        apply(selection, config);
        expect(rows(selection), ['cash']);

        AppScope.instance.riderConfig = _Answers(config);
        await pumpPhone(
          tester,
          const WalletScreen(flags: FeatureFlags.release),
        );
        expect(find.text('Pay in car'), findsOneWidget);
        expect(find.text('Apple Pay'), findsNothing);
        expect(find.text('Card'), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  });

  group('4. the demo build is as before', () {
    testWidgets('iPhone: Apple Pay, Card and pay in car without settings', (
      tester,
    ) async {
      LiveDataOnly.on = false;
      CardEntryPolicy.debugOverride = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final selection = RideSelectionController(
        flags: const FeatureFlags(),
        savedCards: SavedCardsController(store: MemorySavedCardsStore()),
      );
      addTearDown(selection.dispose);
      expect(rows(selection), ['apple', 'cards', 'cash']);

      AppScope.instance.riderConfig = _NeverAnswers();
      await pumpPhone(tester, const WalletScreen());
      expect(find.text('Pay in car'), findsOneWidget);
      expect(find.text('Apple Pay'), findsOneWidget);
      expect(find.text('Add card'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    test('the demo stand-in document keeps the three methods', () async {
      LiveDataOnly.on = false;
      final repo = unreachable();
      addTearDown(repo.dispose);
      final config = await repo.forZone(RiderZones.home.id);
      expect(config.paymentMethods, ['cash', 'card', 'apple_pay']);
    });
  });

  group('5. a served list of all three still shows all three (real app)', () {
    RiderAppConfig served(String others) => RiderAppConfig.fromJson({
      'version': 7,
      'zoneId': RiderZones.home.id,
      'currency': 'SEK',
      'country': 'SE',
      'paymentMethods': ['cash', 'card', 'apple_pay'],
      'paymentOptions': [
        {'method': 'cash', 'status': 'available'},
        {'method': 'card', 'status': others},
        {'method': 'apple_pay', 'status': others},
      ],
    })!;

    testWidgets('taken by the server: Apple Pay, the saved card, pay in car', (
      tester,
    ) async {
      realApp();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final cards = SavedCardsController(store: MemorySavedCardsStore());
      await tester.runAsync(
        () => cards.add(
          number: '4242 4242 4242 4242',
          expMonth: 8,
          expYear: 2040,
          holder: 'Rider A',
        ),
      );
      final card = cards.usable().single.methodBrand;
      final selection = RideSelectionController(
        flags: FeatureFlags.release,
        savedCards: cards,
      );
      addTearDown(selection.dispose);
      apply(selection, served('available'));
      expect(rows(selection), ['apple', card, 'cash']);

      await pumpPicker(tester, selection);
      expect(find.byKey(const ValueKey('pay-with-apple')), findsOneWidget);
      expect(find.byKey(ValueKey('pay-with-$card')), findsOneWidget);
      expect(find.byKey(const ValueKey('pay-with-cash')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on in admin, not taken yet: shown as coming soon', (
      tester,
    ) async {
      realApp();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final selection = picker();
      final config = served('coming_soon');
      apply(selection, config);
      expect(rows(selection), ['cash', 'apple (soon)', 'cards (soon)']);

      AppScope.instance.riderConfig = _Answers(config);
      await pumpPhone(tester, const WalletScreen(flags: FeatureFlags.release));
      expect(find.text('Pay in car'), findsOneWidget);
      expect(find.text('Apple Pay'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

class _NeverAnswers implements RiderConfigRepository {
  @override
  Future<RiderAppConfig> current() => Completer<RiderAppConfig>().future;

  @override
  Future<RiderAppConfig> forZone(String zoneId) =>
      Completer<RiderAppConfig>().future;
}

class _Answers implements RiderConfigRepository {
  _Answers(this.config);
  final RiderAppConfig config;

  @override
  Future<RiderAppConfig> current() async => config;

  @override
  Future<RiderAppConfig> forZone(String zoneId) async => config;
}
