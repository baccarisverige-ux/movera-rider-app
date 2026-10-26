import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_reason_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> phoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('searching reasons stay optional and movera-worded', () {
    final reasons = CancellationReason.forPhase(CancelPhase.searching);
    expect(
      reasons.map((r) => r.id),
      containsAll(['wait_too_long', 'pickup_incorrect']),
    );
    expect(
      reasons.map((r) => r.label).join(' '),
      isNot(contains('Selected wrong pickup')),
    );
    expect(reasons, isNot(contains(CancellationReason.driverNotSuitable)));
  });

  test('matched reasons include driver details and drop search-only items', () {
    final reasons = CancellationReason.forPhase(CancelPhase.matched);
    expect(reasons.map((r) => r.id), contains('driver_not_suitable'));
    expect(reasons.map((r) => r.id), isNot(contains('wait_too_long')));
    expect(reasons.map((r) => r.id), isNot(contains('wrong_ride_option')));
  });

  test('keep vs cancel outcomes', () {
    expect(const CancelOutcome.keep().cancelled, isFalse);
    expect(const CancelOutcome.cancel().reasonId, isNull);
    expect(
      const CancelOutcome.cancel(reasonId: 'plans_changed').reasonId,
      'plans_changed',
    );
  });

  testWidgets('Cancel ride stays disabled until a reason is selected', (
    tester,
  ) async {
    await phoneSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CancelReasonSheet(phase: CancelPhase.searching)),
      ),
    );
    final cancel = find.widgetWithText(TextButton, 'Cancel ride');
    expect(tester.widget<TextButton>(cancel).onPressed, isNull);
    await tester.tap(find.text('Plans changed'));
    await tester.pump();
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);
  });

  testWidgets('Skip cancels without a reason', (tester) async {
    await phoneSurface(tester);
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelReasonSheet(
                context,
                phase: CancelPhase.searching,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(outcome?.cancelled, isTrue);
    expect(outcome?.reasonId, isNull);
  });

  testWidgets('selected reason enables Cancel ride and is stored', (
    tester,
  ) async {
    await phoneSurface(tester);
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelReasonSheet(
                context,
                phase: CancelPhase.matched,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Driver/ride details are not suitable'), findsOneWidget);
    expect(find.text('The wait is taking too long'), findsNothing);
    final cancel = find.widgetWithText(TextButton, 'Cancel ride');
    expect(tester.widget<TextButton>(cancel).onPressed, isNull);
    await tester.tap(find.text('Driver/ride details are not suitable'));
    await tester.pump();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(outcome?.cancelled, isTrue);
    expect(outcome?.reasonId, 'driver_not_suitable');
  });

  testWidgets('Keep ride does not cancel', (tester) async {
    await phoneSurface(tester);
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelReasonSheet(
                context,
                phase: CancelPhase.searching,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep ride'));
    await tester.pumpAndSettle();
    expect(outcome?.cancelled, isFalse);
  });

  testWidgets('backing out of matched cancel reasons keeps the ride', (
    tester,
  ) async {
    await phoneSurface(tester);
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelReasonSheet(
                context,
                phase: CancelPhase.matched,
              );
            },
            child: const Text('open-matched-reasons'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-matched-reasons'));
    await tester.pumpAndSettle();
    expect(find.text('Why are you cancelling?'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(outcome?.cancelled, isFalse);
  });

  testWidgets('Cancel request then shows why, Skip still cancels', (
    tester,
  ) async {
    await phoneSurface(tester);
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelRideSheet(context, takingLonger: false);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel request'), findsOneWidget);
    await tester.tap(find.text('Cancel request'));
    await tester.pumpAndSettle();
    expect(find.text('Why are you cancelling?'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(outcome?.cancelled, isTrue);
    expect(outcome?.reasonId, isNull);
  });
}
