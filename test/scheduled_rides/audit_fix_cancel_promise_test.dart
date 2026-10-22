import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';

/// rider-u226: the time step promised a free cancel "before a driver is
/// assigned" and terms "shown before booking". The fee depends only on
/// the time before pickup (and the ride type's rule), and no terms are
/// shown before booking.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('the time step makes no cancel promise the rules break', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleDateTimeSelector(
          body: const SizedBox.shrink(),
          now: () => DateTime.utc(2026, 9, 26, 10),
          onConfirm: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('before a driver is assigned'), findsNothing);
    expect(find.textContaining('shown before booking'), findsNothing);
    expect(
      find.text(
        'Cancelling is free until a set time before pickup, which depends '
        'on the ride type. Your reservation shows the exact terms.',
      ),
      findsOneWidget,
    );
  });
}
