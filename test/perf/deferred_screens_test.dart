import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/native_maps_config.dart';
import 'package:movera_rider/app/deferred_screens.dart';
import 'package:movera_rider/features/history/presentation/ride_history.dart';
import 'package:movera_rider/features/history/presentation/ride_history_result.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:movera_rider/shared/widgets/deferred_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner 2026-11-03, decisions/servers-test-live.md "Load time" LT-4:
/// Wallet, Ride history, Chat and Google Maps load when first needed; the
/// first open shows a short spinner; nothing is removed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await loadDeferredScreens();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // By name: the screen classes are reached through deferred imports.
  Finder screenNamed(String name) => find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == name,
    skipOffstage: false,
  );

  Future<void> open(WidgetTester tester, Widget Function() screen) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const ValueKey('open'),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => screen())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    final loading = find.byKey(
      const ValueKey('deferred-screen-loading'),
      skipOffstage: false,
    );
    for (var i = 0; i < 20 && loading.evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(loading, findsNothing);
    expect(tester.takeException(), isNull);
  }

  testWidgets('Wallet & Payments still opens, through its loader', (
    tester,
  ) async {
    await open(tester, walletAndPaymentsScreen);
    expect(screenNamed('WalletAndPaymentsScreen'), findsOneWidget);
    expect(find.text('Wallet & Payments'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Payments tab still opens, through its loader', (tester) async {
    await open(tester, () => walletAndPaymentsScreen(initialTab: 1));
    expect(find.text('How would you like\nto pay?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Ride history still opens, through its loader', (tester) async {
    await open(tester, rideHistoryScreen);
    expect(screenNamed('RideHistory'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Chat still opens, through its loader', (tester) async {
    await open(tester, () => chatScreen(driverName: 'Ali'));
    expect(screenNamed('Chat'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Ride history\'s "Book a ride" answer is unchanged', () {
    expect(RideHistory.startBookingResult, rideHistoryStartBookingResult);
    expect(rideHistoryStartBookingResult, 'movera.rideHistory.startBooking');
  });

  testWidgets('the first open shows a short spinner, then the screen', (
    tester,
  ) async {
    final loading = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: DeferredScreen(
          load: () => loading.future,
          builder: (_) => const Text('screen'),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('screen'), findsNothing);
    loading.complete();
    await tester.pump();
    expect(find.text('screen'), findsOneWidget);
  });

  testWidgets('a failed download can be tried again', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeferredScreen(
          load: () async {
            calls += 1;
            if (calls == 1) throw StateError('offline');
          },
          builder: (_) => const Text('screen'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('deferred-screen-back')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('deferred-screen-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.text('screen'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('the first map asks the page for Google Maps', (tester) async {
    final wait = CustomGoogleMap.debugWaitForMaps;
    final request = CustomGoogleMap.requestMaps;
    var asked = 0;
    CustomGoogleMap.debugWaitForMaps = true;
    CustomGoogleMap.requestMaps = () => asked += 1;
    // No Maps engine yet (as on the web before Maps JavaScript loads).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeMapsConfig.channel,
      (_) async => false,
    );
    await NativeMapsConfig.load();
    debugDefaultTargetPlatformOverride = null;
    addTearDown(() {
      CustomGoogleMap.debugWaitForMaps = wait;
      CustomGoogleMap.requestMaps = request;
      NativeMapsConfig.debugReset();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeMapsConfig.channel,
        null,
      );
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
    );
    await tester.pump();
    expect(asked, greaterThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  // B9 "Fast app start" (owner 2026-11-04).
  testWidgets('Help still opens, through its loader', (tester) async {
    await open(tester, () => supportHomeScreen());
    expect(screenNamed('SupportHome'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Help article still opens, through its loader', (tester) async {
    await open(tester, () => helpArticleScreen(title: 'About', body: 'Body'));
    expect(screenNamed('HelpArticle'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Security still opens, through its loader', (tester) async {
    await open(tester, () => securityScreen());
    expect(screenNamed('SecurityPage'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Privacy still opens, through its loader', (tester) async {
    await open(tester, () => privacyScreen());
    expect(screenNamed('PrivacyPage'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Personal info still opens, through its loader', (tester) async {
    await open(tester, () => personalInfoScreen());
    expect(screenNamed('PersonalInfoPage'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('B9: the load-on-open screens are not imported eagerly in lib/', () {
    const screens = [
      'features/support/presentation/support.dart',
      'features/profile/presentation/personal_info.dart',
      'features/profile/presentation/security.dart',
      'features/profile/presentation/privacy.dart',
    ];
    final eager = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.startsWith('import ')) continue;
        final target = screens.where(line.contains);
        if (target.isEmpty) continue;
        final next = i + 1 < lines.length ? lines[i + 1] : '';
        if (line.contains(' deferred as ') || next.contains('deferred as ')) {
          continue;
        }
        // A screen's own folder may import its siblings.
        final folder = target.first.substring(0, target.first.lastIndexOf('/'));
        if (file.path.contains(folder.replaceAll('%20', ' '))) {
          continue;
        }
        eager.add('${file.path}: $line');
      }
    }
    expect(eager, isEmpty);
  });
}
