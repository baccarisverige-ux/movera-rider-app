import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';

void main() {
  testWidgets(
    'busy price edit keeps card visible but disables mutation controls',
    (tester) async {
      var confirms = 0;
      var waits = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PriceBumpCard(
              currentPrice: 250,
              maxPrice: 450,
              steps: const <int>[50, 100],
              busy: true,
              onConfirm: (_) => confirms += 1,
              onKeepWaiting: () => waits += 1,
            ),
          ),
        ),
      );

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);

      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed, isNull);

      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        expect(button.onPressed, isNull);
      }

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(confirms, 0);
      expect(waits, 0);
    },
  );
}
