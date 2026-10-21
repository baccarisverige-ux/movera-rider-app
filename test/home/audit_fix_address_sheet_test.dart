import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Location services off: Home has no fix and labels the pickup
/// 'Location off, set pickup'.
class _OffGeolocator extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;
}

class _MemAddresses extends HomeAddressRepository {
  HomeAddressSnapshot snapshot = HomeAddressSnapshot();

  @override
  Future<HomeAddressSnapshot> load() async => snapshot;

  @override
  Future<void> save(HomeAddressSnapshot data) async {
    snapshot = data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;
  });

  Future<void> frames(WidgetTester tester, int count, {int ms = 100}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(Duration(milliseconds: ms));
    }
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    await frames(tester, 8);
  }

  Future<void> tearDownHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 40));
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> openSetWork(WidgetTester tester) async {
    await tester.drag(find.byType(WhereToCard), const Offset(0, -400));
    await frames(tester, 10);
    await tester.tap(find.text('Set Work'));
    await frames(tester, 6);
  }

  testWidgets('rider-u123: with the keyboard open the Home/Work address '
      'sheet sits on the keyboard, fits and takes taps', (tester) async {
    await pumpHome(tester);
    await openSetWork(tester);
    // An iPhone keyboard opens under the autofocused field.
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await frames(tester, 6);
    await tester.enterText(find.byType(TextField).last, 'Kungsgatan 1');
    await frames(tester, 6);
    expect(tester.takeException(), isNull);
    final button = find.text('Use this address');
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.bottom, lessThanOrEqualTo(844 - 336));
    // Not lifted a second keyboard height above the keyboard.
    expect(rect.bottom, greaterThan(844 - 336 - 120));
    await tester.tap(button);
    await frames(tester, 10);
    expect(find.text('Set Work address', skipOffstage: false), findsNothing);
    await tearDownHome(tester);
  });

  testWidgets('rider-46: with location off, Use current location does not '
      'save the placeholder as Work', (tester) async {
    final previous = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _OffGeolocator();
    addTearDown(() => GeolocatorPlatform.instance = previous);
    await pumpHome(tester);
    await openSetWork(tester);
    final row = find.text('Use current location');
    expect(row, findsOneWidget);
    await tester.tap(row);
    await frames(tester, 10);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('movera_work_address'), isNull);
    expect(
      prefs.getStringList('movera_recent_addresses') ?? const <String>[],
      isNot(contains('Location off, set pickup')),
    );
    await tearDownHome(tester);
  });

  test('rider-46: placeholders and raw coordinates never become Recents', () {
    final places = HomePlacesController(store: _MemAddresses());
    places.remember('Location off, set pickup');
    places.remember('59.329300, 18.068600');
    places.remember('Current location');
    places.applyResolved(target: 'home', address: 'Location off, set pickup');
    expect(places.recentAddresses, isEmpty);
    expect(places.homeAddress, isNull);
  });
}
