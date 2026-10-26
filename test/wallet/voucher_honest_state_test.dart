import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/wallet/presentation/wallet.dart';

void main() {
  testWidgets('voucher action explains that redemption is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showVoucherUnavailableSheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.confirmation_number_outlined), findsOneWidget);
    expect(find.text('Vouchers aren’t available yet'), findsOneWidget);
    expect(find.textContaining('when the service launches'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
