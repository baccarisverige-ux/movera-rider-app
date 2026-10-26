import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/presentation/ride_completed.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.tripCompleted;
  });

  Future<void> navigationViewport(WidgetTester tester) async {
    // This suite verifies navigation/state behavior, not the legacy responsive
    // layout of RideCompleted. Give the existing screen enough room so an
    // unrelated pre-existing RenderFlex overflow cannot mask navigation bugs.
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app() {
    return ScreenUtilInit(
      designSize: const Size(1200, 1600),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        navigatorKey: moveraNavigatorKey,
        home: const Scaffold(body: Text('home-root')),
      ),
    );
  }

  testWidgets('RideCompleted Done returns to root and closes the ride', (
    tester,
  ) async {
    await navigationViewport(tester);
    await tester.pumpWidget(app());

    moveraNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const RideCompleted()),
    );
    await tester.pumpAndSettle();

    // The completion surface must not close the ride before the rider leaves it.
    expect(AppScope.instance.ride.status, RideStatus.tripCompleted);

    final done = find.byKey(const ValueKey<String>('ride-completed-done'));
    expect(done, findsOneWidget);
    await tester.tap(done);
    await tester.pumpAndSettle();

    expect(find.text('home-root'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    expect(moveraNavigatorKey.currentState!.canPop(), isFalse);
    expect(AppScope.instance.ride.status, RideStatus.closed);
  });

  testWidgets('RideCompleted back affordance returns to root', (tester) async {
    await navigationViewport(tester);
    await tester.pumpWidget(app());

    moveraNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const RideCompleted()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
    await tester.pumpAndSettle();

    expect(find.text('home-root'), findsOneWidget);
    expect(moveraNavigatorKey.currentState!.canPop(), isFalse);
    expect(AppScope.instance.ride.status, RideStatus.closed);
  });
}
