import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'Schedule Continue is accessible and stale pickup is corrected before navigation',
    (tester) async {
      var now = DateTime.utc(2026, 9, 26, 10);
      var confirms = 0;

      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleDateTimeSelector(
            body: const SizedBox.shrink(),
            now: () => now,
            onConfirm: () => confirms += 1,
          ),
        ),
      );
      await tester.pump();

      final continueControl = find.byKey(const Key('schedule-continue'));
      expect(continueControl, findsOneWidget);

      // The button was built while 12:30 Stockholm was legal. Advance the
      // injected clock across the next slot boundary without rebuilding first:
      // this reproduces the real wall-clock race at the moment of the tap.
      now = DateTime.utc(2026, 9, 26, 10, 6);
      await tester.tap(continueControl);
      await tester.pump();

      expect(confirms, 0);
      expect(
        find.text('Pickup time updated to the next available slot.'),
        findsOneWidget,
      );

      // After the correction rebuilds the real button with a legal pickup, the
      // next deliberate tap advances immediately.
      await tester.tap(find.byKey(const Key('schedule-continue')));
      await tester.pump();
      expect(confirms, 1);
    },
  );
}
