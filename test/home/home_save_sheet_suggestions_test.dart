import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/widgets/where_to_card.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saved places v4 (owner 2026-11-27): Home's save-address sheet shows the
/// real suggestions while typing (the shared AddressSuggestionList), not
/// only recent addresses, and a pick saves that address.
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

  testWidgets('Home save sheet: suggestions while typing; a pick saves it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
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
    await frames(tester, 8);
    await tester.drag(find.byType(WhereToCard), const Offset(0, -400));
    await frames(tester, 10);
    await tester.tap(find.text('Set Work'));
    await frames(tester, 6);

    await tester.enterText(find.byType(TextField).last, 'Friend');
    await frames(tester, 15);
    expect(
      find.byKey(const ValueKey('address-suggestions')),
      findsOneWidget,
      reason: 'no suggestions in the Home save-address sheet',
    );
    final pick = find.byKey(const ValueKey('address-suggestion-0'));
    expect(pick, findsOneWidget);
    await tester.tap(pick);
    await frames(tester, 15);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('movera_work_address'), contains('Friend'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 40));
    debugDefaultTargetPlatformOverride = null;
  });
}
