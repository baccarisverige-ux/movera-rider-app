import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/screen_scale.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R-UI UI-05: with two stops, at 320x568 and text 1.3 or in landscape web
/// (844x390), the route change sheet overflowed — "Confirm · next: payment"
/// was clipped and "Keep current route" was off-screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final quote = RouteChangeQuote(
    pickupAddress: 'Sveavägen 1, 111 57 Stockholm',
    pickupPoint: const GeoPoint(59.33, 18.06),
    destinationAddress: 'Stockholm Arlanda Airport, Terminal 5, Arlanda',
    destinationPoint: const GeoPoint(59.65, 17.93),
    stops: const [
      RouteStop(
        address: 'Odenplan, Stockholm',
        latitude: 59.34,
        longitude: 18.05,
      ),
      RouteStop(
        address: 'Hornsgatan 2, Stockholm',
        latitude: 59.32,
        longitude: 18.06,
      ),
    ],
    oldPriceKr: 300,
    newPriceKr: 420,
  );

  for (final (name, size, scale) in const <(String, Size, double)>[
    ('320x568 at text 1.3', Size(320, 568), 1.3),
    ('844x390 landscape', Size(844, 390), 1.0),
  ]) {
    testWidgets('two stops fit and both actions are reachable: $name', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      RouteChangeDecision? decision;
      await tester.pumpWidget(
        MoveraScreenUtilInit(
          builder: (_, __) => MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      decision = await RouteChangeSheet.confirm(
                        context,
                        quote: quote,
                        paymentMethod: 'Visa •••• 4242',
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');

      final keep = find.text('Keep current route');
      final confirm = find.byKey(const ValueKey('route-change-confirm'));
      for (final target in [keep, confirm]) {
        final center = tester.getCenter(target);
        expect(center.dy, lessThan(size.height), reason: 'on screen');
        expect(
          tester
              .hitTestOnBinding(center)
              .path
              .any((entry) => entry.target == tester.renderObject(target)),
          isTrue,
          reason: 'tappable',
        );
      }

      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('route-change-pay')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('route-change-pay')));
      await tester.pumpAndSettle();
      expect(decision?.confirmed, isTrue);
    });
  }
}
