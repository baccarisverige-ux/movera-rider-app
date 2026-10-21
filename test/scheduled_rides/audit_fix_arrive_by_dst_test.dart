import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';

/// Audit fix review: "Arrive by" subtracted the trip from the wall-clock
/// fields. On the spring-forward night, a pickup in the skipped hour was
/// moved an hour later, after the chosen arrival. The pickup must be real
/// elapsed time before the arrival. Only bites where the device zone has
/// DST (Architecture gates also runs this file with TZ=Europe/Stockholm).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final now = DateTime.utc(2027, 3, 27, 10);
  final original = StockholmSchedule.clock;
  setUp(() => StockholmSchedule.clock = () => now);
  tearDown(() => StockholmSchedule.clock = original);

  testWidgets('a pickup in the skipped DST hour is never after the arrival', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final arrival = DateTime(2027, 3, 28, 3, 10);
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await ScheduleDateTimeSelector.choose(
                context,
                initial: arrival,
                now: () => now,
                tripMinutes: 20,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arrive by'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Schedule Continue'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.isAfter(arrival), isFalse, reason: 'pickup $picked');
    expect(
      arrival.difference(picked!),
      greaterThanOrEqualTo(const Duration(minutes: 20)),
    );
  });
}
