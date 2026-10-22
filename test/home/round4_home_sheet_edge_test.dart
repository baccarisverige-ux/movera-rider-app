import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/widgets/home_sheet_edge.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner round 4: the Home sheet has square corners and is raised over the
/// map by an upward shadow, the same edge as the sign-in card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false;
  });

  test('the edge is white, square and cast upward', () {
    const d = HomeSheetEdge.decoration;
    expect(d.color, Colors.white);
    expect(d.borderRadius, isNull, reason: 'no rounded corners');
    expect(d.border, isNull);
    expect(d.boxShadow, hasLength(2));
    for (final shadow in d.boxShadow!) {
      expect(shadow.offset.dx, 0);
      expect(shadow.offset.dy, lessThan(0), reason: 'raised over the map');
      expect(shadow.color.a, lessThan(0.2), reason: 'soft, not a dark bar');
    }
    expect(
      d.boxShadow!.first.blurRadius,
      greaterThan(d.boxShadow!.last.blurRadius),
    );
  });

  testWidgets('the Home sheet uses that edge', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        MoveraScreenUtilInit(
          builder: (_, __) =>
              MaterialApp(navigatorKey: moveraNavigatorKey, home: const Home()),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final surface = find.byKey(const ValueKey('home-sheet-surface'));
      expect(surface, findsOneWidget);
      final box = tester.widget<Container>(surface);
      expect(box.decoration, HomeSheetEdge.decoration);
      // Edge to edge, down to the bottom of the screen.
      final rect = tester.getRect(surface);
      expect(rect.left, 0);
      expect(rect.right, 390);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
