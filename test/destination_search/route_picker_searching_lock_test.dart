import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Audit N2 (apps-every-control 2026-11-20): while the ride is still
/// searching, the locked pickup must not say "Din förare är redan på väg".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester tester, {bool? driverOnTheWay}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: RoutePickerPage(
          pageTitle: 'Change route',
          pickupAddress: 'Sergels torg 1',
          destinationAddress: 'Odenplan 2',
          stops: const [],
          stopsSupported: true,
          pickupLocked: true,
          driverOnTheWay: driverOnTheWay ?? true,
          initialField: 'destination',
          capture: EarlyInputCapture(),
          here: const GeoPoint(59.33, 18.06),
          homeAddress: null,
          workAddress: null,
          recent: const [],
          onSetFavourite: (_) async => null,
          onPickOnMap: ({required pickup, required address}) async => null,
          onFinish: (_) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('searching: locked pickup, no "driver on the way" text', (
    tester,
  ) async {
    await pump(tester, driverOnTheWay: false);
    expect(
      find.byKey(const ValueKey('route-picker-pickup-locked')),
      findsOneWidget,
    );
    expect(find.byTooltip(L10n.current.routeDriverOnTheWay), findsNothing);
  });

  testWidgets('driver accepted: the "driver on the way" text stays', (
    tester,
  ) async {
    await pump(tester, driverOnTheWay: true);
    expect(find.byTooltip(L10n.current.routeDriverOnTheWay), findsOneWidget);
  });
}
