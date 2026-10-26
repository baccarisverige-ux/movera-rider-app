import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web lifecycle: on the web every Google map a screen mounts is a map the
/// page keeps (google_maps_flutter_web registers each one for the life of
/// the page), so Home must not mount one for the moment between Plan your
/// ride closing and the categories screen opening. Measured before this,
/// one booking created six maps; Home alone accounted for two of them.
Future<void> _waitFor(WidgetTester t, Finder f, {int tries = 50}) async {
  for (var i = 0; i < tries && f.evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const _homeMap = ValueKey('home-map');

/// The picker's own close control.
final _pickerClose = find
    .descendant(
      of: find.byType(RoutePickerPage),
      matching: find.byIcon(Icons.close_rounded),
    )
    .first;

/// Lets a route transition finish and Home's post-frame parking run.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

int _homeMapsMounted() =>
    CustomGoogleMap.debugMounted.where((key) => key == _homeMap).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    CustomGoogleMap.debugMounted.clear();
  });
  tearDown(CustomGoogleMap.debugMounted.clear);

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
    await tester.pumpWidget(
      MoveraScreenUtilInit(
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_homeMapsMounted(), 1, reason: 'Home mounts its map once');
  }

  Future<void> tearDownHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets(
    'Plan your ride to the categories screen mounts no Home map in between',
    (tester) async {
      await pumpHome(tester);

      await tester.tap(find.text('Where to?'));
      await _waitFor(tester, find.byType(RoutePickerPage));
      await _settle(tester);
      // Plan your ride covers Home: the map is parked, not remounted.
      expect(find.byKey(_homeMap, skipOffstage: false), findsNothing);
      expect(_homeMapsMounted(), 1);

      await tester.enterText(find.byType(TextField).at(0), 'Stockholm Central');
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'Arlanda Airport');
      await tester.pump();
      final pick = find.textContaining(
        'Stockholm Arlanda Airport',
        findRichText: true,
      );
      await _waitFor(tester, pick, tries: 30);
      await tester.tap(pick.first);
      await _waitFor(tester, find.byType(SelectRide), tries: 40);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(SelectRide), findsOneWidget);
      expect(
        _homeMapsMounted(),
        1,
        reason: 'Home remounted its map between the picker and Select ride',
      );
      expect(find.byKey(_homeMap, skipOffstage: false), findsNothing);

      // Back on the categories screen reopens Plan your ride with the same
      // route (owner round 1): Home stays covered, still without a map.
      moveraNavigatorKey.currentState!.pop();
      await _waitFor(tester, find.byType(RoutePickerPage));
      await _settle(tester);
      expect(find.byType(SelectRide), findsNothing);
      expect(find.byKey(_homeMap, skipOffstage: false), findsNothing);
      expect(_homeMapsMounted(), 1);

      // Closing Plan your ride ends the flow: Home gets its map back.
      await tester.tap(_pickerClose);
      await _settle(tester);
      expect(find.byType(RoutePickerPage), findsNothing);
      expect(find.byKey(_homeMap), findsOneWidget);
      expect(_homeMapsMounted(), 2);

      await tearDownHome(tester);
    },
  );

  testWidgets('closing Plan your ride gives Home its map back at once', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.text('Where to?'));
    await _waitFor(tester, find.byType(RoutePickerPage));
    await _settle(tester);
    expect(find.byKey(_homeMap, skipOffstage: false), findsNothing);

    await tester.tap(_pickerClose);
    // Well inside the grace Home gives a running flow.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(RoutePickerPage), findsNothing);
    expect(find.byKey(_homeMap), findsOneWidget);
    expect(_homeMapsMounted(), 2);

    await tearDownHome(tester);
  });
}
