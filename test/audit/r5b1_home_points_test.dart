import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pin = GeoPoint(59.3401, 18.0402);
const _gate = GeoPoint(59.6519, 17.9186);

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens Where to? from Home and finishes it with [selection], as the
/// picker does.
Future<void> _finish(
  WidgetTester tester,
  RoutePickerSelection selection,
) async {
  final picker = find.byType(RoutePickerPage);
  final draft = await tester
      .widget<RoutePickerPage>(picker)
      .onFinish(selection);
  Navigator.of(tester.element(picker)).pop(draft);
  for (var i = 0; i < 40 && find.byType(SelectRide).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false;
  });

  testWidgets('rider-r5-36/37: picked points reach Select Ride and come '
      'back to Where to?', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
      ),
    );
    await _frames(tester, 8);
    await tester.tap(find.text('Where to?'));
    await _frames(tester, 20);
    await _finish(
      tester,
      const RoutePickerSelection(
        pickup: 'Sveavägen 1, Stockholm',
        pickupPoint: GeoPoint(59.3326, 18.0649),
        destination: 'Arlanda gate 5',
        destinationPoint: _gate,
        stops: ['Pickup location'],
        stopPoints: [_pin],
      ),
    );
    final select = tester.widget<SelectRide>(find.byType(SelectRide));
    expect(select.stopPoints, [_pin]);

    // Owner round 1: Back first reopens Where to? on the same points.
    moveraNavigatorKey.currentState!.pop();
    await _frames(tester, 15);
    final reopened = tester.widget<RoutePickerPage>(
      find.byType(RoutePickerPage),
    );
    expect(reopened.destinationPoint?.latitude, _gate.latitude);
    expect(reopened.stopPoints.single?.latitude, _pin.latitude);
    moveraNavigatorKey.currentState!.pop();
    await _frames(tester, 15);
    expect(find.byType(RoutePickerPage), findsNothing);

    // rider-r5-37: back on Home, Where to? opens on the same points.
    await tester.tap(
      find.descendant(
        of: find.byType(WhereToCard),
        matching: find.byIcon(Icons.search_rounded),
      ),
    );
    await _frames(tester, 20);
    final again = tester.widget<RoutePickerPage>(find.byType(RoutePickerPage));
    expect(again.destinationPoint?.latitude, _gate.latitude);
    expect(again.stopPoints.single?.latitude, _pin.latitude);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  });
}
