import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/web/web_search_interrupted.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _notice =
    'Your ride search was interrupted. Book again when you are ready.';

RideSnapshot _live() => RideSnapshot(
  status: RideStatus.driverArriving,
  savedAt: DateTime.now(),
  pickupAddress: 'A',
  destinationAddress: 'B',
  pickupLat: 59.3,
  pickupLng: 18.0,
  destinationLat: 59.6,
  destinationLng: 17.9,
  rideType: 'Movera',
  price: 259,
  paymentMethod: 'cash',
  rideId: 'ride_1',
  version: 3,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RideSnapshotStore.epoch = 0;
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle;
  });
  tearDown(() => debugTakeWebSearchInterrupted = null);

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tearDownHome(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('rider-u117: Home says nothing about an interrupted search '
      'while the kept ride is still stored (sign-in mid-ride on the web)', (
    tester,
  ) async {
    await RideSnapshotStore.save(_live());
    var taken = 0;
    debugTakeWebSearchInterrupted = () {
      taken += 1;
      return taken == 1;
    };
    await pumpHome(tester);
    expect(taken, 1);
    expect(find.text(_notice), findsNothing);
    await tearDownHome(tester);
  });

  testWidgets('rider-u117: with no ride stored the web note is still shown', (
    tester,
  ) async {
    var taken = 0;
    debugTakeWebSearchInterrupted = () {
      taken += 1;
      return taken == 1;
    };
    await pumpHome(tester);
    expect(find.text(_notice), findsOneWidget);
    await tearDownHome(tester);
  });
}
