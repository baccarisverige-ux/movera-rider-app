import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';

/// Wave 5 R5.2 parts a+b, on screen: no success text the app did not get.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Pumps a page with one button that runs [open], and taps it.
  Future<void> openFrom(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'rider-u36: the sheet shows the server\'s difference, not the device\'s',
      (tester) async {
    // The device still holds 259 kr; the server already charged the earlier
    // (lost) change, so this quote's difference is 0.
    await openFrom(tester, (context) => RouteChangeSheet.confirm(
          context,
          quote: const RouteChangeQuote(
            pickupAddress: 'Sergels torg 1',
            pickupPoint: GeoPoint(59.33, 18.06),
            destinationAddress: 'Arlanda',
            destinationPoint: GeoPoint(59.65, 17.93),
            stops: [],
            oldPriceKr: 259,
            newPriceKr: 308,
            newTotalMinor: 30800,
            differenceMinor: 0,
          ),
          paymentMethod: 'Visa •••• 4242',
        ));
    expect(find.textContaining('49 kr'), findsNothing);
    expect(find.textContaining('charged to'), findsNothing);
  });
}
