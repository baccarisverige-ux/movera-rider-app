import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/features/ride_complete/presentation/server_receipt_lines.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Fix job 0 (owner A2-2, contract 0.18.29 `outstandingFee.receiptText`): an
/// unpaid fee is added by itself to the rider's next trip; that trip's receipt
/// shows the line AND says in words what it is (sv / fr / en).
void main() {
  Future<void> pump(
    WidgetTester tester,
    Locale locale,
    Map<String, Object?> json,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ServerReceiptLines(
            rideId: 'trp_2',
            loader: (_) async => ServerReceipt.tryParse(json),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the next trip\'s receipt explains the earlier unpaid fee (sv)', (
    tester,
  ) async {
    await pump(tester, const Locale('sv'), {
      'tripId': 'trp_2',
      'debtIncluded': {'amountMinor': 4000, 'currency': 'SEK'},
    });
    expect(find.byKey(const ValueKey('receipt-debt')), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-debt-note')), findsOneWidget);
    final note = tester.widget<Text>(
      find.byKey(const ValueKey('receipt-debt-note')),
    );
    // The app's own language (English in tests) is shown; sv / fr come from the same key.
    expect(
      note.data,
      'An unpaid fee from an earlier trip was added to this trip.',
    );
    expect(
      lookupAppLocalizations(const Locale('sv')).receiptDebtIncludedNote,
      'En obetald avgift från en tidigare resa har lagts till på den här resan.',
    );
  });

  testWidgets('France: the note in French', (tester) async {
    await pump(tester, const Locale('fr'), {
      'tripId': 'trp_3',
      'debtIncluded': {'amountMinor': 500, 'currency': 'EUR'},
    });
    expect(
      lookupAppLocalizations(const Locale('fr')).receiptDebtIncludedNote,
      'Des frais impayés d’un trajet précédent ont été ajoutés à ce trajet.',
    );
    expect(find.byKey(const ValueKey('receipt-debt-note')), findsOneWidget);
  });

  testWidgets('no owed fee: no note', (tester) async {
    await pump(tester, const Locale('en'), {'tripId': 'trp_4'});
    expect(find.byKey(const ValueKey('receipt-debt-note')), findsNothing);
  });
}
