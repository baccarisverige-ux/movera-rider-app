import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';

/// Q9: Book later times are the pickup zone's local time.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // 20 Oct 2026, 10:00 UTC: summer time in Sweden and France (UTC+2),
  // Tunisia is UTC+1 all year.
  final summer = DateTime.utc(2026, 10, 20, 10);
  // 20 Jan 2026, 10:00 UTC: everyone on UTC+1.
  final winter = DateTime.utc(2026, 1, 20, 10);

  test('each zone has its own wall clock', () {
    expect(ZoneClock.wallTime(ZoneClock.stockholm, summer), DateTime.utc(2026, 10, 20, 12));
    expect(ZoneClock.wallTime(ZoneClock.paris, summer), DateTime.utc(2026, 10, 20, 12));
    expect(ZoneClock.wallTime(ZoneClock.tunis, summer), DateTime.utc(2026, 10, 20, 11));
    expect(ZoneClock.wallTime(ZoneClock.tunis, winter), DateTime.utc(2026, 1, 20, 11));
    expect(ZoneClock.wallTime(ZoneClock.paris, winter), DateTime.utc(2026, 1, 20, 11));
  });

  test('a booked wall time is the right instant in its zone', () {
    final wall = DateTime.utc(2026, 10, 20, 18, 30);
    expect(ZoneClock.toUtc(wall, ZoneClock.stockholm), DateTime.utc(2026, 10, 20, 16, 30));
    expect(ZoneClock.toUtc(wall, ZoneClock.tunis), DateTime.utc(2026, 10, 20, 17, 30));
    // Across the October change (25 Oct 2026, 01:00 UTC).
    expect(
      ZoneClock.toUtc(DateTime.utc(2026, 10, 26, 9), ZoneClock.paris),
      DateTime.utc(2026, 10, 26, 8),
    );
  });

  test('the earliest pickup follows the pickup zone', () {
    expect(
      const PickupSchedule(ZoneClock.tunis).minimumPickup(summer),
      DateTime.utc(2026, 10, 20, 11, 30),
    );
    expect(
      const PickupSchedule(ZoneClock.stockholm).minimumPickup(summer),
      DateTime.utc(2026, 10, 20, 12, 30),
    );
    // 11:45 in Tunis is bookable now; in Stockholm it is the past.
    final tunisLater = DateTime.utc(2026, 10, 20, 11, 45);
    expect(const PickupSchedule(ZoneClock.tunis).isLegalPickup(tunisLater, summer), isTrue);
    expect(StockholmSchedule.isLegalPickup(tunisLater, summer), isFalse);
  });

  test('a pickup point picks its zone', () {
    expect(PickupSchedule.at(36.80, 10.18).timeZone, ZoneClock.tunis);
    expect(PickupSchedule.at(48.86, 2.35).timeZone, ZoneClock.paris);
    expect(PickupSchedule.at(59.33, 18.06).timeZone, ZoneClock.stockholm);
  });

  testWidgets('the picker opens on the pickup zone\'s first slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DateTime? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              chosen = await ScheduleDateTimeSelector.choose(
                context,
                now: () => summer,
                timeZone: ZoneClock.tunis,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final next = find.text('Continue');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(chosen, DateTime.utc(2026, 10, 20, 11, 30));
  });
}
