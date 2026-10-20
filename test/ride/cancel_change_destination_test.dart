import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_reason_sheet.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Q2: "Destination needs to be changed" offers the route change first;
/// the rider can still cancel.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  Future<CancelOutcome? Function()> open(
    WidgetTester tester, {
    bool offer = true,
    bool committed = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    CancelOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showCancelReasonSheet(
                context,
                phase: CancelPhase.matched,
                committed: committed,
                offerDestinationChange: offer,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => outcome;
  }

  final offer = find.byKey(const ValueKey('cancel-change-destination-offer'));

  testWidgets('the destination reason offers Change destination instead', (
    tester,
  ) async {
    final outcome = await open(tester);
    expect(offer, findsNothing);
    await tester.tap(find.text('Destination needs to be changed'));
    await tester.pump();
    expect(find.text('Change destination instead?'), findsOneWidget);
    // Another reason hides the offer again.
    await tester.tap(find.text('Plans changed'));
    await tester.pump();
    expect(offer, findsNothing);

    await tester.tap(find.text('Destination needs to be changed'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cancel-change-destination')));
    await tester.pumpAndSettle();
    expect(outcome()?.changeDestination, isTrue);
    expect(outcome()?.cancelled, isFalse);
  });

  testWidgets('the rider can still cancel for that reason', (tester) async {
    final outcome = await open(tester);
    await tester.tap(find.text('Destination needs to be changed'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel ride'));
    await tester.pumpAndSettle();
    expect(outcome()?.cancelled, isTrue);
    expect(outcome()?.reasonId, 'destination_change');
    expect(outcome()?.changeDestination, isFalse);
  });

  testWidgets('no offer where the ride cannot change any more', (
    tester,
  ) async {
    await open(tester, offer: false);
    await tester.tap(find.text('Destination needs to be changed'));
    await tester.pump();
    expect(offer, findsNothing);
  });

  testWidgets('Waiting\'s cancel flow hands the choice back, nothing cancelled',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
                offerDestinationChange: true,
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
    await tester.tap(find.text('Destination needs to be changed'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cancel-change-destination')));
    await tester.pumpAndSettle();
    expect(outcome?.changeDestination, isTrue);
    expect(outcome?.cancelled, isFalse);
  });
}
