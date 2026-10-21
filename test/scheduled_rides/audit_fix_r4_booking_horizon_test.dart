import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/config/zone_clock.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';

/// rider-r4-10: the zone config's bookingHorizonDays was parsed but never
/// enforced; Book for later allowed any date up to a year ahead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a pickup past the zone horizon is brought back inside it', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 20, 10);
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
                initial: DateTime(2026, 11, 10, 9),
                now: () => now,
                horizonDays: 7,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.text('Rides can be booked up to 7 days ahead. Pickup time updated.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('schedule-continue')));
    await tester.pumpAndSettle();

    final booked = ZoneClock.toUtc(picked!, ZoneClock.stockholm);
    expect(booked.isAfter(now.add(const Duration(days: 7))), isFalse);
    expect(
      const PickupSchedule(ZoneClock.stockholm).isLegalPickup(picked!, now),
      isTrue,
    );
  });
}
