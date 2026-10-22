import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';

/// Audit fix review: "Arrive by" across a DST change. On the spring-forward
/// night a pickup in the skipped hour was moved after the arrival; on the
/// fall-back night a pickup in the first copy of the repeated hour was
/// booked as the second copy, an hour late. The booked pickup (read in the
/// pickup zone, as the booking does) must be at least the trip before the
/// arrival. Only bites where the device zone has DST: Architecture gates
/// also runs this file with TZ=Europe/Stockholm and TZ=America/New_York.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final original = StockholmSchedule.clock;
  tearDown(() => StockholmSchedule.clock = original);

  Future<void> expectNotLate(
    WidgetTester tester, {
    required DateTime now,
    required DateTime arrival,
    required int trip,
  }) async {
    StockholmSchedule.clock = () => now;
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
                tripMinutes: trip,
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
    await tester.tap(find.byKey(const Key('schedule-continue')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    final booked = ZoneClock.toUtc(picked!, ZoneClock.stockholm);
    final arrives = ZoneClock.toUtc(arrival, ZoneClock.stockholm);
    final lead = arrives.difference(booked);
    expect(
      lead,
      greaterThanOrEqualTo(Duration(minutes: trip)),
      reason: 'pickup $picked booked $booked, arrival $arrives',
    );
    expect(lead, lessThan(Duration(minutes: trip + 60)));
  }

  testWidgets('spring forward: a pickup in the skipped hour is not late', (
    tester,
  ) async {
    await expectNotLate(
      tester,
      now: DateTime.utc(2027, 3, 27, 10),
      arrival: DateTime(2027, 3, 28, 3, 10),
      trip: 20,
    );
  });

  testWidgets('fall back: a pickup in the repeated hour is not booked late', (
    tester,
  ) async {
    await expectNotLate(
      tester,
      now: DateTime.utc(2026, 10, 24, 10),
      arrival: DateTime(2026, 10, 25, 3, 10),
      trip: 80,
    );
  });

  testWidgets('the trip is subtracted in the pickup zone, not the device '
      'zone (US fall-back night, no change in Stockholm)', (tester) async {
    await expectNotLate(
      tester,
      now: DateTime.utc(2026, 10, 31, 10),
      arrival: DateTime(2026, 11, 1, 2, 10),
      trip: 80,
    );
  });

  test('rider-r4-12: a pickup in the spring-forward gap is booked as the '
      'time it really is, never an hour later than shown', () {
    final now = DateTime.utc(2026, 3, 27, 10);
    const stockholm = PickupSchedule(ZoneClock.stockholm);
    final picked = stockholm.clampPickup(DateTime.utc(2026, 3, 29, 2, 30), now);
    expect(picked, DateTime.utc(2026, 3, 29, 3, 30));
    expect(
      ZoneClock.wallTime(ZoneClock.stockholm, stockholm.toUtc(picked)),
      picked,
    );
  });
}
