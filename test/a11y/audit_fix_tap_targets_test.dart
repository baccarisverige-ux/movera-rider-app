import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/navigator_key.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/app/theme/app_theme.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/home/presentation/home.dart';
import 'package:movera_rider/features/home/presentation/side_menu.dart';
import 'package:movera_rider/features/profile/application/profile_controller.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/presentation/account_home.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UI-4 / UI-5 / UI-6: every tap target on the main screens is at least
/// 44 x 44 (iOS HIG), every tappable node has a label, and text passes
/// Flutter's contrast check, at a common phone size and at 320 x 568.
///
/// Screens run on the host platform (no map platform view in tests) with the
/// phone density and tap-target padding, so desktop-compact IconButtons do
/// not count.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FindingDriverController.active = null;
    AppScope.instance.ride
      ..rideId = null
      ..status = RideStatus.idle
      ..suppressRestore = false
      ..authoritativeVersion = null
      ..authoritativeUpdatedAt = null;
  });

  const pickup = LatLng(59.3293, 18.0686);
  const destination = LatLng(59.3326, 18.0649);

  final screens = <String, Widget Function()>{
    'Home': () => const Home(),
    'Home expanded': () => const Home(),
    'Route picker': () => RoutePickerPage(
      pickupAddress: 'Sergels torg 1, 111 57 Stockholm',
      destinationAddress: 'Odenplan 2, 113 22 Stockholm',
      stops: const ['Hötorget 1'],
      stopsSupported: true,
      initialField: 'destination',
      finishLabel: 'See prices',
      capture: EarlyInputCapture(),
      here: const GeoPoint(59.33, 18.06),
      homeAddress: 'Kungsgatan 12, Stockholm',
      workAddress: null,
      recent: const ['Drottninggatan 50, Stockholm'],
      onSetFavourite: (_) async => null,
      onPickOnMap: ({required pickup, required address}) async => null,
      onFinish: (_) async => null,
    ),
    'Select ride': () => const SelectRide(
      pickupAddress: 'Sergels torg 1, 111 57 Stockholm',
      destinationAddress: 'Odenplan 2, 113 22 Stockholm',
      pickupPosition: pickup,
      destinationPosition: destination,
    ),
    'Menu': () => const RiderMenuPage(),
    'Account': () => AccountHomePage(
      controller: ProfileController(
        store: ProfileRepository(storageKey: 'audit_fix_tap_profile'),
      ),
    ),
    'Payments': () => const WalletAndPaymentsScreen(),
    'Payments tab 2': () => const WalletAndPaymentsScreen(initialTab: 1),
  };

  for (final entry in screens.entries) {
    for (final size in const [Size(390, 844), Size(320, 568)]) {
      final name =
          '${entry.key} @ ${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('$name: targets ≥ 44, labelled, readable', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MoveraScreenUtilInit(
              builder: (_, __) => MaterialApp(
                navigatorKey: moveraNavigatorKey,
                theme: moveraTheme().copyWith(
                  visualDensity: VisualDensity.standard,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
                home: entry.value(),
              ),
            ),
          );
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (entry.key == 'Home expanded') {
            final handle = find.bySemanticsLabel('Toggle home panel');
            expect(handle, findsWidgets);
            await tester.timedDrag(
              handle.first,
              const Offset(0, -700),
              const Duration(milliseconds: 300),
              warnIfMissed: false,
            );
            for (var i = 0; i < 15; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        } finally {
          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 2));
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  testWidgets('Home top actions and nav reach 48 x 48 on a phone', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
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
      for (final label in ['Menu', 'Saved Places']) {
        final node = tester.getSemantics(find.bySemanticsLabel(label).first);
        final rect = _globalRect(node);
        expect(rect.width, greaterThanOrEqualTo(48), reason: label);
        expect(rect.height, greaterThanOrEqualTo(48), reason: label);
      }
      for (final label in ['Home', 'Payment', 'Schedule ride']) {
        final node = tester.getSemantics(
          find.bySemanticsLabel(RegExp('^$label\n')).first,
        );
        expect(_globalRect(node).height, greaterThanOrEqualTo(48));
      }
    } finally {
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// The node's rect in logical screen pixels (its transforms applied).
Rect _globalRect(SemanticsNode node) {
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    final transform = n.transform;
    if (transform != null) {
      rect = MatrixUtils.transformRect(transform, rect);
    }
  }
  return rect;
}
