import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/auth/token_store.dart';
import 'package:movera_rider/features/auth/presentation/sign_in.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/profile/application/account_deletion_controller.dart';
import 'package:movera_rider/features/profile/data/account_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/profile/presentation/delete_account.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:movera_rider/features/ride_booking/presentation/ride_restore_gate.dart';
import 'package:movera_rider/features/safety/data/sos_sender.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FLOW-2 / NAV-4: Sign out and Delete account are reachable, confirm first,
/// land on Sign in under the root gate and leave no rider data behind.

const _rider = <String, Object>{
  'movera_home_address': 'Rider A home',
  'movera_profile_v1': '{"name":"Rider A"}',
  'movera_wallet_balance': 150.0,
  'movera_saved_cards': '[]',
  'movera_active_ride': '{}',
};

Future<void> _pumpApp(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  // Signed in (the token store follows the platform override).
  await AppScope.instance.tokens.save(access: 'a', refresh: 'b');
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        navigatorKey: moveraNavigatorKey,
        home: RideRestoreGate(key: RideRestoreGate.gateKey),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  moveraNavigatorKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => page),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  RideRestoreCoordinator.instance.showing = RestoredSurface.home;
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  debugDefaultTargetPlatformOverride = null;
}

Future<List<String>> _riderKeysLeft() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getKeys().where((key) => key.startsWith('movera_')).toList();
}

Future<void> _tapRow(WidgetTester tester, String label) async {
  // The page on top owns the last Scrollable; rows below the fold are
  // built only once scrolled to.
  await tester.scrollUntilVisible(
    find.text(label),
    120,
    scrollable: find.byType(Scrollable).last,
  );
  final row = find.text(label).last;
  await tester.ensureVisible(row);
  await tester.pump();
  await tester.tap(row);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() async {
    // Launch build: SosSender keeps its write chain in a static (rider #680,
    // contract v0.18.148); one left by the test before sits in that test's
    // fake clock and the next sign-out would wait on it forever.
    await SosSender.resetForTesting();
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{..._rider});
  });

  testWidgets('Account: Sign out asks first, then lands on Sign in wiped', (
    tester,
  ) async {
    await _pumpApp(tester, const AccountHomePage());
    await _tapRow(tester, 'Sign out');
    expect(find.text('Sign out?'), findsOneWidget);

    // Cancel keeps the rider signed in.
    await tester.tap(find.byKey(const ValueKey('sign-out-cancel')));
    await _settle(tester);
    expect(find.byType(SignIn), findsNothing);
    expect(await AppScope.instance.auth.hasSession(), isTrue);

    await _tapRow(tester, 'Sign out');
    await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);

    expect(find.byType(SignIn), findsOneWidget);
    expect(find.byType(AccountHomePage), findsNothing);
    expect(find.byType(RideRestoreGate), findsOneWidget, reason: 'root gate');
    expect(await AppScope.instance.auth.hasSession(), isFalse);
    expect(await _riderKeysLeft(), isEmpty);
    await _unmount(tester);
  });

  testWidgets('Menu: Sign out lands on Sign in wiped', (tester) async {
    await _pumpApp(tester, const RiderMenuPage());
    await _tapRow(tester, 'Sign out');
    await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);

    expect(find.byType(SignIn), findsOneWidget);
    expect(find.byType(RiderMenuPage), findsNothing);
    expect(find.byType(RideRestoreGate), findsOneWidget);
    expect(await AppScope.instance.auth.hasSession(), isFalse);
    expect(await _riderKeysLeft(), isEmpty);
    await _unmount(tester);
  });

  testWidgets('Delete account: explains, confirms, sends, then signs out', (
    tester,
  ) async {
    await _pumpApp(tester, const AccountHomePage());
    await _tapRow(tester, 'Delete account');
    expect(find.byType(DeleteAccountPage), findsOneWidget);
    expect(find.text('Your places'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);

    await _tapRow(tester, 'Delete my account');
    expect(find.text('Delete your account?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);

    expect(find.text('Your deletion request was sent'), findsOneWidget);
    expect(await AppScope.instance.auth.hasSession(), isFalse);
    expect(await _riderKeysLeft(), isEmpty);

    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(find.byType(SignIn), findsOneWidget);
    expect(find.byType(RideRestoreGate), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Delete account: a refused request keeps the rider and data', (
    tester,
  ) async {
    final tokens = MemoryTokenStore();
    final failing = AccountDeletionController(
      repository: AccountRepository(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response('{"code":"UNAVAILABLE"}', 503),
          ),
          tokens: tokens,
        ),
      ),
    );
    await _pumpApp(tester, DeleteAccountPage(controller: failing));
    await _tapRow(tester, 'Delete my account');
    await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);

    expect(find.text('Your deletion request was sent'), findsNothing);
    expect(find.textContaining("couldn't send your request"), findsOneWidget);
    expect(await AppScope.instance.auth.hasSession(), isTrue);
    expect(await _riderKeysLeft(), containsAll(_rider.keys));
    await _unmount(tester);
  });
}
