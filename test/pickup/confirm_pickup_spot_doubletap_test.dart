import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';

/// Phase 133: confirm_pickup_spot.dart's _confirmPosition did a bare
/// synchronous Navigator.pop with no guard, so a fast double-tap right as
/// the exit transition starts could pop this screen *and* the one beneath
/// it. Reproduces by tapping Confirm twice before a frame is pumped, and
/// asserting only ConfirmPickupSpot itself closes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a double-tap on Confirm pickup spot only pops once', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Center(child: Text('beneath'))),
      ),
    );

    ConfirmPickupResult? result;
    unawaited(
      navigatorKey.currentState!
          .push<ConfirmPickupResult?>(
            MaterialPageRoute(
              builder: (_) => const ConfirmPickupSpot(
                initialPosition: LatLng(59.19, 17.62),
                initialAddress: 'Klockarvägen 37',
              ),
            ),
          )
          .then((value) => result = value),
    );
    await tester.pumpAndSettle();

    expect(find.text('beneath'), findsNothing);
    expect(find.byType(ConfirmPickupSpot), findsOneWidget);

    final confirmButton = find.widgetWithText(FilledButton, 'Confirm pickup');
    // Two taps back to back, before any frame is pumped in between - the
    // same conditions a fast double-tap produces.
    await tester.tap(confirmButton, warnIfMissed: false);
    await tester.tap(confirmButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      find.text('beneath'),
      findsOneWidget,
      reason: 'only ConfirmPickupSpot should have popped, not the screen beneath it',
    );
    expect(find.byType(ConfirmPickupSpot), findsNothing);
    expect(result, isNotNull);
  });
}
