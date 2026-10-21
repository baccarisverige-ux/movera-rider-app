import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:movera_rider/features/scheduled_rides/application/stockholm_schedule.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/select_date_time.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// rider-89: "Arrive by" booked the chosen arrival time as the pickup.
/// rider-88: Continue stayed disabled as "Continuing…" once the next step
/// came back. rider-90 (this screen's part): the time sheet's "24-hour"
/// caption was English in every language.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // 12:00 in Stockholm (CEST): the earliest pickup is 12:30.
  final now = DateTime.utc(2026, 9, 26, 10);
  final original = StockholmSchedule.clock;
  setUp(() => StockholmSchedule.clock = () => now);
  tearDown(() => StockholmSchedule.clock = original);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> tapContinue(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Schedule Continue'));
    await tester.pumpAndSettle();
  }

  group('rider-89: Arrive by books arrival minus the trip', () {
    testWidgets('returns the pickup and shows both times', (tester) async {
      phone(tester);
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await ScheduleDateTimeSelector.choose(
                  context,
                  initial: DateTime(2026, 9, 26, 14),
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
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('Estimated pickup'), findsOneWidget);
      expect(find.text('13:40'), findsOneWidget);

      await tapContinue(tester);
      expect(picked, DateTime(2026, 9, 26, 13, 40));
    });

    testWidgets('an off-slot pickup is rounded earlier, never late', (
      tester,
    ) async {
      phone(tester);
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await ScheduleDateTimeSelector.choose(
                  context,
                  initial: DateTime(2026, 9, 26, 14),
                  now: () => now,
                  tripMinutes: 22,
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
      // 14:00 - 22 min = 13:38, booked on the 13:35 slot.
      expect(find.text('13:35'), findsOneWidget);
      await tapContinue(tester);
      expect(picked, DateTime(2026, 9, 26, 13, 35));
    });

    testWidgets('the embedded flow stores the pickup in the session', (
      tester,
    ) async {
      phone(tester);
      final session = ScheduledRideSession()
        ..captureSchedule(DateTime(2026, 9, 26, 14));
      var confirms = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleDateTimeSelector(
            body: const SizedBox.shrink(),
            session: session,
            now: () => now,
            tripMinutes: 20,
            onConfirm: () => confirms++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arrive by'));
      await tester.pumpAndSettle();
      await tapContinue(tester);
      expect(confirms, 1);
      expect(session.scheduledAt, DateTime(2026, 9, 26, 13, 40));
    });

    testWidgets('an arrival too soon for the trip moves to the first one', (
      tester,
    ) async {
      phone(tester);
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await ScheduleDateTimeSelector.choose(
                  context,
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
      expect(find.text('12:30'), findsOneWidget);

      // Arriving by 12:30 would need a 12:10 pickup, before the earliest.
      await tester.tap(find.text('Arrive by'));
      await tester.pumpAndSettle();
      expect(find.text('12:50'), findsOneWidget);
      expect(find.text('12:30'), findsOneWidget);
      expect(
        find.text('Pickup time updated to the next available slot.'),
        findsOneWidget,
      );
      await tapContinue(tester);
      expect(picked, DateTime(2026, 9, 26, 12, 30));
    });

    testWidgets('without a trip estimate the time stays a pickup time', (
      tester,
    ) async {
      phone(tester);
      DateTime? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await ScheduleDateTimeSelector.choose(
                  context,
                  initial: DateTime(2026, 9, 26, 14),
                  now: () => now,
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
      FontWeight? weight(String label) =>
          tester.widget<Text>(find.text(label)).style?.fontWeight;
      expect(weight('Pickup at'), FontWeight.w600);
      expect(weight('Arrive by'), FontWeight.w500);
      await tapContinue(tester);
      expect(picked, DateTime(2026, 9, 26, 14));
    });
  });

  testWidgets(
    'rider-88: Continue is usable again once the next step comes back',
    (tester) async {
      phone(tester);
      var confirms = 0;
      var step = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => ScheduleDateTimeSelector(
              body: const SizedBox.shrink(),
              session: ScheduledRideSession(),
              now: () => now,
              tripMinutes: 20,
              // Same shape as ScheduleRide.goToNextStep: the category
              // cards are open until the future completes, then the host
              // rebuilds.
              onConfirm: () async {
                confirms++;
                await step.future;
                setState(() {});
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Schedule Continue'));
      await tester.pump();
      expect(confirms, 1);
      expect(find.text('Continuing…'), findsOneWidget);
      // Still locked while the next step is open.
      await tester.tap(find.bySemanticsLabel('Schedule Continue'));
      await tester.pump();
      expect(confirms, 1);

      step.complete();
      await tester.pumpAndSettle();
      expect(find.text('Continuing…'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).enabled,
        isTrue,
      );

      step = Completer<void>();
      await tester.tap(find.bySemanticsLabel('Schedule Continue'));
      await tester.pump();
      expect(confirms, 2);
      step.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('rider-90: the time sheet caption is translated', (
    tester,
  ) async {
    phone(tester);
    addTearDown(() => L10n.use('en'));
    L10n.use('fr');
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleDateTimeSelector(
          body: const SizedBox.shrink(),
          session: ScheduledRideSession()
            ..captureSchedule(DateTime(2026, 9, 26, 14)),
          now: () => now,
          onConfirm: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('14:00'));
    await tester.pumpAndSettle();
    expect(find.text(L10n.current.selectTime), findsOneWidget);
    expect(find.text('24 h'), findsOneWidget);
    expect(find.text('24-hour'), findsNothing);
  });
}
