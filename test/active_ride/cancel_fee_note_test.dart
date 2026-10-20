import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/finding_driver/domain/cancellation_reason.dart';
import 'package:movera_rider/features/finding_driver/presentation/cancel_ride_sheet.dart';

/// Contract v0.3.0 §5: the rider sees the cancel fee before confirming.
void main() {
  Future<void> pump(WidgetTester tester, String? note) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CancelRideSheet(
          takingLonger: false,
          phase: CancelPhase.matched,
          feeNote: note,
        ),
      ),
    ),
  );

  testWidgets('the fee line shows under the body', (tester) async {
    await pump(tester, 'Cancelling now costs 35 kr.');
    expect(find.text('Cancelling now costs 35 kr.'), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel-fee-note')), findsOneWidget);
  });

  testWidgets('no rule, no line', (tester) async {
    await pump(tester, null);
    expect(find.byKey(const ValueKey('cancel-fee-note')), findsNothing);
  });
}
