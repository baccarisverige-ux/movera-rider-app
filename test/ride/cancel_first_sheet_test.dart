import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';

/// Cancellation orchestration must remain reversible until the final action.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> phoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('first confirmation does not commit cancellation', (tester) async {
    await phoneSurface(tester);
    final order = <String>[];
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelRideSheet(
                context,
                takingLonger: false,
                onCancelConfirmed: () async {
                  order.add('cancelled');
                },
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();

    expect(order, isEmpty);
    expect(find.text('Why are you cancelling?'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(order, ['cancelled']);
    expect(outcome?.cancelled, isTrue);
  });

  testWidgets('Keep ride after first confirmation keeps the ride', (tester) async {
    await phoneSurface(tester);
    var committed = false;
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelRideSheet(
                context,
                takingLonger: false,
                onCancelConfirmed: () async {
                  committed = true;
                },
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();

    expect(committed, isFalse);
    await tester.tap(find.text('Keep ride'));
    await tester.pumpAndSettle();

    expect(outcome?.cancelled, isFalse);
    expect(committed, isFalse);
  });


  testWidgets('matched-driver cancel stays reversible until the final step', (
    tester,
  ) async {
    await phoneSurface(tester);
    var committed = false;
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelRideSheet(
                context,
                takingLonger: false,
                phase: CancelPhase.matched,
                onCancelConfirmed: () async {
                  committed = true;
                },
              );
            },
            child: const Text('open-matched-cancel'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-matched-cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();

    expect(committed, isFalse);
    expect(find.text('Why are you cancelling?'), findsOneWidget);

    await tester.tap(find.text('Keep ride'));
    await tester.pumpAndSettle();

    expect(outcome?.cancelled, isFalse);
    expect(committed, isFalse);
  });

  testWidgets('active-trip cancel is reversible until the final step', (
    tester,
  ) async {
    await phoneSurface(tester);
    var committed = false;
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelRideSheet(
                context,
                takingLonger: false,
                phase: CancelPhase.inTrip,
                onCancelConfirmed: () async {
                  committed = true;
                },
              );
            },
            child: const Text('open-active-trip-cancel'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-active-trip-cancel'));
    await tester.pumpAndSettle();
    // UI-01: on board this ends the trip early (paid by distance).
    expect(find.text('End trip here?'), findsOneWidget);
    expect(find.textContaining('pay for the distance driven'), findsOneWidget);
    await tester.tap(find.text('End trip here'));
    await tester.pumpAndSettle();

    expect(committed, isFalse);
    expect(find.text('Why are you ending the trip?'), findsOneWidget);

    await tester.tap(find.text('Keep ride'));
    await tester.pumpAndSettle();

    expect(outcome?.cancelled, isFalse);
    expect(committed, isFalse);
  });
}
