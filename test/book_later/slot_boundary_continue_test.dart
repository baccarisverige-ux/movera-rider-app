import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';

/// Main run 43719084054 ("QA live Rider flow", 2905386a): the Book later
/// date-and-time page opened at 13:30:5x UTC (14:30 Stockholm), so its
/// earliest slot was 15:00. Continue was tapped at about 13:31:00.2 UTC,
/// after 15:00 stopped being 30 minutes away. rider-u227 then moved the
/// time to 15:05 and kept the page open ("Time 15:05", "Continue" on
/// screen), and the QA script, which tapped Continue only once, waited
/// 20 s for Select ride. These tests pin that minute.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() => StockholmSchedule.clock = DateTime.now);

  // 2026-11-15 is CET (UTC+1).
  final opened = DateTime.utc(2026, 11, 15, 13, 30, 57);
  final tapped = DateTime.utc(2026, 11, 15, 13, 31, 0, 200);

  test('the 15:00 slot shown at 14:30:57 is stale at 14:31:00.2', () {
    final schedule = PickupSchedule.stockholm;
    final shown = schedule.defaultPickup(opened);
    expect(shown, DateTime.utc(2026, 11, 15, 15));
    expect(schedule.isLegalPickup(shown, opened), isTrue);
    expect(schedule.isLegalPickup(shown, tapped), isFalse);
    expect(schedule.minimumPickup(tapped), DateTime.utc(2026, 11, 15, 15, 5));
  });

  testWidgets('a Continue that crosses the slot boundary corrects the time; '
      'a second Continue books the corrected slot', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    var now = opened;
    StockholmSchedule.clock = () => now;
    var confirmed = 0;
    final session = ScheduledRideSession();
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleDateTimeSelector(
          body: const SizedBox.shrink(),
          session: session,
          now: () => now,
          onConfirm: () => confirmed++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('15:00'), findsWidgets);

    now = tapped;
    await tester.tap(find.byKey(const Key('schedule-continue')));
    await tester.pumpAndSettle();
    expect(confirmed, 0, reason: 'the page stays open (rider-u227)');
    expect(find.text('15:05'), findsWidgets);
    expect(
      find.text('Pickup time updated to the next available slot.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('schedule-continue')));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(session.scheduledAt, DateTime.utc(2026, 11, 15, 15, 5));
  });

  test('QA live Rider flow taps Continue again when the slot moved', () {
    final yml = File(
      '.github/workflows/qa-live-rider-flow.yml',
    ).readAsStringSync();
    final start = yml.indexOf("'Continue','Book later: date and time'");
    final end = yml.indexOf("'select_ride','Book later: categories'");
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final step = yml.substring(start, end);
    expect(
      step,
      contains('Pickup time updated to the next available slot.'),
      reason: 'the script must see the rider-u227 correction',
    );
    expect(
      step,
      contains("'Continue','Book later: date and time (moved slot)'"),
      reason: 'and tap Continue once more',
    );
  });
}
