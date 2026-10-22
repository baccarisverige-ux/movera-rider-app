import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('rider-r5-33: letters typed before Where to? opens start a '
      'search', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final capture = EarlyInputCapture()..start();
    addTearDown(capture.stop);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    for (final c in 'oden'.split('')) {
      await simulateKeyDownEvent(
        LogicalKeyboardKey(c.codeUnitAt(0)),
        character: c,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: RoutePickerPage(
          pickupAddress: 'Sveavägen 1, Stockholm',
          destinationAddress: '',
          stops: const [],
          stopsSupported: true,
          initialField: 'destination',
          capture: capture,
          here: const GeoPoint(59.33, 18.06),
          homeAddress: null,
          workAddress: null,
          recent: const ['Kungsgatan 3, Stockholm', 'Odengatan 5, Stockholm'],
          onPickOnMap: ({required pickup, required address}) async => null,
          onFinish: (_) async => null,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Odengatan'), findsWidgets);
    expect(find.textContaining('Kungsgatan'), findsNothing);
  });
}
