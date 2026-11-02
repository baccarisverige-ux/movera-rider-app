import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/demo_features.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/home/presentation/widgets/advance_booking_card.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/shared/widgets/app_icon_asset.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/features/profile/application/account_security_controller.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/account_security_repository.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/profile/presentation/privacy.dart';
import 'package:movera_rider/features/ride_selection/application/ride_catalog_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live clean-up (full audit 2026-11-02, rider H1/H2/H7/M1/M2/M3/M5/M6).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => DemoFeatures.debugOverride = null);

  Future<void> pumpPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(home: home),
      ),
    );
    await tester.pump();
  }

  (AccountSecurityController, List<String>) security({required bool built}) {
    final calls = <String>[];
    final controller = AccountSecurityController(
      built: built,
      repository: AccountSecurityRepository(
        api: ApiClient(
          env: const AppEnv(
            flavor: AppFlavor.staging,
            apiBaseUrl: 'https://api.staging.movera.example',
          ),
          client: MockClient((request) async {
            calls.add(request.url.path);
            return http.Response(jsonEncode({'error': 'not_found'}), 404);
          }),
        ),
      ),
    );
    return (controller, calls);
  }

  test('M3: no /account/security call while it is not built', () async {
    final (controller, calls) = security(built: false);
    await controller.load();
    expect(calls, isEmpty);
  });

  testWidgets('M3: Account hides Security while it is not built', (
    tester,
  ) async {
    final (controller, calls) = security(built: false);
    await pumpPhone(
      tester,
      AccountHomePage(
        controller: ProfileController(
          store: ProfileRepository(storageKey: 'live_cleanup'),
        ),
        securityController: controller,
      ),
    );
    expect(find.text('Security'), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('M6: Privacy hides e-mail and offers switches on live', (
    tester,
  ) async {
    DemoFeatures.debugOverride = false;
    await pumpPhone(
      tester,
      PrivacyPage(
        controller: ProfileController(
          store: ProfileRepository(storageKey: 'live_cleanup_p'),
        ),
      ),
    );
    expect(find.text('Ride updates'), findsOneWidget);
    expect(find.text('Offers'), findsNothing);
  });

  testWidgets('Owner 2026-11-02: the Later button and the Book ahead card '
      'with its picture are back on home', (tester) async {
    var taps = 0;
    await pumpPhone(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              WhereToCard(
                destinationAddress: null,
                onDestinationTap: () {},
                onOpenSchedule: () => taps++,
              ),
              AdvanceBookingCard(onOpenSchedule: () => taps++),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Later'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is AppIconAsset && w.asset == AppAssets.solarCalendar,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is ResizeImage &&
            ((w.image as ResizeImage).imageProvider as AssetImage).assetName ==
                'assets/images/advance_booking_driver.webp',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Later'));
    await tester.ensureVisible(find.byType(AdvanceBookingCard));
    await tester.tap(find.byType(AdvanceBookingCard));
    expect(taps, 2);
  });

  test('M5: a France zone never falls back to SEK', () {
    final config = RiderAppConfig.fromJson({
      'version': 1,
      'currency': 'EUR',
      'catalog': {
        'categories': [
          {'id': 'economy', 'label': 'Movera', 'seats': 4, 'sort': 1},
          {'id': 'van_new', 'label': 'Van', 'seats': 7, 'sort': 2},
        ],
      },
    })!;
    final items = RideCatalogController.fromConfig(
      config.categories,
      RideSelectionRepository.builtInRides,
      currency: config.currency,
    );
    expect(items.map((i) => i.currency).toSet(), {'EUR'});
  });

  test('H2: pickup chips are labelled approximate in sv / fr / en', () {
    for (final (lang, word) in [
      ('en', 'approximate'),
      ('sv', 'ungefärlig'),
      ('fr', 'approximatif'),
    ]) {
      expect(
        lookupAppLocalizations(Locale(lang)).pickupSpotApproximate('X'),
        'X ($word)',
      );
    }
  });

  // H7 (no Visa / Mastercard / Google / Apple marks outside sign-in) is a repo
  // gate in .github/workflows/ci.yml (it scans lib/, not behaviour).

  for (final demo in [false, true]) {
    testWidgets('M2: menu coming-soon cards follow DemoFeatures (on: $demo)', (
      tester,
    ) async {
      DemoFeatures.debugOverride = demo;
      await pumpPhone(tester, const RiderMenuPage());
      await tester.pump(const Duration(milliseconds: 300));
      for (final title in ['Movera Family', 'Movera Business']) {
        expect(
          find.text(title),
          demo ? findsWidgets : findsNothing,
          reason: title,
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
