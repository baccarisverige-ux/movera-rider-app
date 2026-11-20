import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_terminal_state_sheet.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_complete/application/server_receipt.dart';
import 'package:movera_rider/features/ride_complete/presentation/server_receipt_lines.dart';
import 'package:movera_rider/l10n/l10n.dart';

Map<String, Object?> _money(int minor) => {
  'amountMinor': minor,
  'currency': 'SEK',
};

Map<String, Object?> _line(String code, int minor) => {
  'code': code,
  'amount': _money(minor),
};

/// The receipt of the 2026-11-19 click-through: a booked ride with an added
/// stop, 4 kr waiting at the stop, total 235 kr. Lines as movera-server
/// sends them (`GET /trips/{id}/receipt` `fareLines`, the rider's lines).
Map<String, Object?> _receipt({List<Object?>? lines, int total = 23500}) => {
  'tripId': 'trp_1',
  'total': _money(total),
  'paymentMethod': 'cash',
  'cashPaid': _money(total),
  'fareLines':
      lines ??
      [
        _line('base', 4500),
        _line('distance', 9000),
        _line('time', 3000),
        _line('stops', 2000),
        _line('stop_waiting', 400),
        _line('reservation_fee', 2500),
        _line('app_fee', 2130),
        _line('pickup_fee', 0),
        _line('rounding', -30),
      ],
};

/// R6 (owner 2026-11-20, "Yes, all 7 as drafts"): the rider's receipt
/// showed only the total; the stop waiting (+4 kr) and an old unpaid fee
/// (35 kr) were not explained. The receipt now shows the server's own
/// lines; the phone adds nothing up.
void main() {
  Future<void> pump(WidgetTester tester, Map<String, Object?> json) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServerReceiptLines(
              rideId: 'trp_1',
              loader: (_) async => ServerReceipt.tryParse(json),
              showTotal: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String rowText(WidgetTester tester, String key) => tester
      .widgetList<Text>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Text),
        ),
      )
      .map((text) => text.data)
      .join(' | ');

  test('the receipt keeps the server lines in order, without the 0 lines', () {
    final receipt = ServerReceipt.tryParse(_receipt())!;
    expect(
      [for (final line in receipt.fareLines) line.code],
      [
        'base',
        'distance',
        'time',
        'stops',
        'stop_waiting',
        'reservation_fee',
        'app_fee',
        'rounding',
      ],
    );
    expect(receipt.fareLines[4].amount.amountMinor, 400);
    expect(receipt.fareLines.last.amount.amountMinor, -30);
  });

  testWidgets('the stop waiting is its own line with the server amount', (
    tester,
  ) async {
    await pump(tester, _receipt());
    expect(find.byKey(const ValueKey('receipt-lines-heading')), findsOneWidget);
    expect(
      rowText(tester, 'receipt-line-stop_waiting'),
      'Waiting at stops | 4,00 kr',
    );
    expect(rowText(tester, 'receipt-line-stops'), 'Extra stops | 20,00 kr');
    expect(
      rowText(tester, 'receipt-line-reservation_fee'),
      'Booking fee for a booked ride | 25,00 kr',
    );
    expect(rowText(tester, 'receipt-line-base'), 'Start fee | 45,00 kr');
    // A minus line keeps its sign.
    expect(rowText(tester, 'receipt-line-rounding'), 'Rounding | −0,30 kr');
    // A line of 0 is not listed; the total is the server's total.
    expect(find.byKey(const ValueKey('receipt-line-pickup_fee')), findsNothing);
    expect(rowText(tester, 'receipt-total'), 'Total | 235,00 kr');
  });

  testWidgets('an old unpaid fee paid with this trip is explained, once', (
    tester,
  ) async {
    await pump(tester, {
      ..._receipt(
        total: 9400,
        lines: [
          _line('base', 4500),
          _line('distance', 1400),
          _line('outstanding_fee', 3500),
        ],
      ),
      'debtIncluded': _money(3500),
    });
    expect(
      rowText(tester, 'receipt-line-outstanding_fee'),
      'Earlier unpaid fee | 35,00 kr',
    );
    // Not a second time as the separate line; the words stay.
    expect(find.byKey(const ValueKey('receipt-debt')), findsNothing);
    expect(find.text('35,00 kr'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-debt-note')), findsOneWidget);
  });

  testWidgets('a line code this app does not know is still shown', (
    tester,
  ) async {
    await pump(
      tester,
      _receipt(lines: [_line('base', 4500), _line('bridge_toll', 1200)]),
    );
    expect(rowText(tester, 'receipt-line-bridge_toll'), 'Other | 12,00 kr');
  });

  testWidgets('two lines of one code are both shown', (tester) async {
    await pump(
      tester,
      _receipt(
        lines: [_line('outstanding_fee', 3500), _line('outstanding_fee', 6500)],
      ),
    );
    expect(
      rowText(tester, 'receipt-line-outstanding_fee'),
      'Earlier unpaid fee | 35,00 kr',
    );
    expect(
      rowText(tester, 'receipt-line-outstanding_fee-1'),
      'Earlier unpaid fee | 65,00 kr',
    );
  });

  testWidgets('a list the app cannot read whole is not shown in part', (
    tester,
  ) async {
    await pump(
      tester,
      _receipt(
        lines: [
          _line('base', 4500),
          {'code': 'distance'},
        ],
      ),
    );
    expect(find.byKey(const ValueKey('receipt-lines-heading')), findsNothing);
    expect(find.byKey(const ValueKey('receipt-line-base')), findsNothing);
    expect(rowText(tester, 'receipt-total'), 'Total | 235,00 kr');
    // Another currency than the receipt's: not shown either.
    expect(
      ServerReceipt.tryParse(
        _receipt(
          lines: [
            {
              'code': 'base',
              'amount': {'amountMinor': 450, 'currency': 'EUR'},
            },
          ],
        ),
      )!.fareLines,
      isEmpty,
    );
  });

  test('every contract line code has its own words in sv, fr and en', () {
    const codes = [
      'base',
      'distance',
      'time',
      'fixed_route',
      'surge',
      'minimum_adjust',
      'maximum_adjust',
      'waiting',
      'stops',
      'stop_waiting',
      'extras',
      'airport',
      'reservation_fee',
      'app_fee',
      'pickup_fee',
      'rounding',
      'discount',
      'cancel_fee',
      'outstanding_fee',
      'rider_raise',
    ];
    for (final language in const ['sv', 'fr', 'en']) {
      final l10n = lookupAppLocalizations(Locale(language));
      final labels = {for (final c in codes) receiptFareLineLabel(l10n, c)};
      expect(labels, hasLength(codes.length), reason: language);
      expect(labels, isNot(contains(l10n.receiptLineOther)), reason: language);
    }
    final sv = lookupAppLocalizations(const Locale('sv'));
    expect(receiptFareLineLabel(sv, 'stop_waiting'), 'Väntetid vid stopp');
    expect(receiptFareLineLabel(sv, 'outstanding_fee'), sv.receiptDebtIncluded);
  });

  testWidgets('no-show: the fee is said once, not after "a fee may apply"', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRideEndedSearchAgainSheet(
              context,
              status: RideStatus.noShow,
              feeLine: 'No-show fee 65,00 kr',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No-show fee 65,00 kr'), findsOneWidget);
    expect(find.textContaining('may apply'), findsNothing);
    expect(
      find.textContaining('the ride was closed as a no-show.'),
      findsOneWidget,
    );
  });

  testWidgets('no-show with no fee known keeps the old words', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRideEndedSearchAgainSheet(
              context,
              status: RideStatus.noShow,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A no-show fee may apply.'), findsOneWidget);
  });
}
