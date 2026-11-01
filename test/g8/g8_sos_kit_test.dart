import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/realtime/sos_availability.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v0.18.10 (owner G8 Q4): the safety kit shows SOS only when the server's
/// sosAvailable says so; without it, once a driver has the trip.
void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(SosAvailability.resetForTest);

  Future<void> open(WidgetTester tester, {bool driverAssigned = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRideSafetyKit(
              context,
              rideId: 'trp_sos',
              driverAssigned: driverAssigned,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('server says no SOS: only Call 112', (tester) async {
    SosAvailability.record('trp_sos', false);
    await open(tester);
    expect(find.byKey(const ValueKey('safety-sos')), findsNothing);
    expect(find.byKey(const ValueKey('safety-call-112')), findsOneWidget);
  });

  testWidgets('server says SOS: SOS even before the app saw a driver', (
    tester,
  ) async {
    SosAvailability.record('trp_sos', true);
    await open(tester, driverAssigned: false);
    expect(find.byKey(const ValueKey('safety-sos')), findsOneWidget);
  });

  testWidgets('no word from the server: the driver rule', (tester) async {
    await open(tester, driverAssigned: false);
    expect(find.byKey(const ValueKey('safety-sos')), findsNothing);
    expect(find.byKey(const ValueKey('safety-call-112')), findsOneWidget);
  });
}
