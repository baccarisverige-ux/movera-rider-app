import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/data/saved_cards_store.dart';
import 'package:movera_rider/features/payments/presentation/add_card_page.dart';
import 'package:movera_rider/features/payments/presentation/pay_with_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const visa = SavedCard(
    id: 'c1',
    brand: 'visa',
    last4: '4242',
    expMonth: 8,
    expYear: 2028,
    holder: 'Anna Berg',
  );

  Widget brandMark(String brand) => SizedBox(
    key: ValueKey('mark-$brand'),
    width: 42,
    height: 38,
  );

  Future<void> pumpPayWith(
    WidgetTester tester, {
    required List<PayWithMethod> methods,
    String? selected,
    SavedCardsController? cards,
  }) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => PayWithPage.open(
                  context,
                  methods: methods,
                  selectedBrand: selected,
                  walletBalance: 0,
                  promotion: null,
                  brandMark: brandMark,
                  savedCards: cards,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(PayWithPage), findsOneWidget);
  }

  testWidgets('saved cards are rows with brand mark, expiry and radio', (
    tester,
  ) async {
    final methods = [
      const PayWithMethod(brand: 'google', name: 'Google Pay', detail: 'Pays'),
      PayWithMethod(
        brand: visa.methodBrand,
        name: visa.displayName,
        detail: 'Expires ${visa.expiryLabel}',
      ),
      const PayWithMethod(brand: 'cards', name: 'Card', detail: 'Visa, Mastercard'),
      const PayWithMethod(brand: 'cash', name: 'Cash', detail: 'Cash'),
    ];
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await PayWithPage.open(
                context,
                methods: methods,
                selectedBrand: 'card:c1',
                walletBalance: 0,
                promotion: null,
                brandMark: brandMark,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Visa •••• 4242'), findsOneWidget);
    expect(find.text('Expires 08/28'), findsOneWidget);
    expect(find.byKey(const ValueKey('mark-card:c1')), findsOneWidget);
    // The generic Card row hides once a card is saved.
    expect(find.text('Visa, Mastercard'), findsNothing);
    // The saved card is the selected one.
    final row = find.byKey(const ValueKey('pay-with-card:c1'));
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('pay-with-cash')));
    await tester.pumpAndSettle();
    expect(popped, 'cash');
  });

  testWidgets('without saved cards the generic Card row stays', (tester) async {
    await pumpPayWith(
      tester,
      methods: const [
        PayWithMethod(brand: 'cards', name: 'Card', detail: 'Visa, Mastercard'),
        PayWithMethod(brand: 'cash', name: 'Cash', detail: 'Cash'),
      ],
      selected: 'cash',
    );
    expect(find.text('Card'), findsOneWidget);
    expect(find.text('Visa, Mastercard'), findsOneWidget);
    expect(find.text('Add payment method'), findsOneWidget);
  });

  testWidgets('Add payment method saves a card and selects it', (tester) async {
    final cards = SavedCardsController(store: MemorySavedCardsStore());
    String? popped;
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await PayWithPage.open(
                context,
                methods: const [
                  PayWithMethod(
                    brand: 'cards',
                    name: 'Card',
                    detail: 'Visa, Mastercard',
                  ),
                  PayWithMethod(brand: 'cash', name: 'Cash', detail: ''),
                ],
                selectedBrand: 'cash',
                walletBalance: 0,
                promotion: null,
                brandMark: brandMark,
                savedCards: cards,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pay-with-add')));
    await tester.pumpAndSettle();
    expect(find.byType(AddCardPage), findsOneWidget);

    final save = find.byKey(const ValueKey('add-card-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('add-card-number')),
      '4242424242424242',
    );
    await tester.pump();
    // Auto-spaced in groups of four.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('add-card-number')))
          .controller!
          .text,
      '4242 4242 4242 4242',
    );
    await tester.enterText(find.byKey(const ValueKey('add-card-expiry')), '0828');
    await tester.enterText(find.byKey(const ValueKey('add-card-cvc')), '123');
    await tester.enterText(
      find.byKey(const ValueKey('add-card-holder')),
      'Anna Berg',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('add-card-expiry')))
          .controller!
          .text,
      '08/28',
    );
    // The preview follows the typed details.
    final preview = find.byKey(const ValueKey('add-card-preview'));
    expect(
      find.descendant(of: preview, matching: find.text('ANNA BERG')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: preview, matching: find.text('08/28')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await tester.pumpAndSettle();

    // Add card popped with the card, and Pay with popped with it selected.
    expect(find.byType(AddCardPage), findsNothing);
    expect(find.byType(PayWithPage), findsNothing);
    expect(cards.list().single.last4, '4242');
    expect(popped, 'card:${cards.list().single.id}');
  });

  testWidgets('Add card rejects other brands and expired dates', (tester) async {
    final cards = SavedCardsController(store: MemorySavedCardsStore());
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: AddCardPage(cards: cards, now: DateTime(2026, 10, 13))),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('add-card-number')),
      '6011111111111117',
    );
    await tester.pump();
    expect(find.text('We accept Visa and Mastercard'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('add-card-number')),
      '4242424242424242',
    );
    await tester.enterText(find.byKey(const ValueKey('add-card-expiry')), '0925');
    await tester.pump();
    expect(find.text('We accept Visa and Mastercard'), findsNothing);
    expect(find.text('This card has expired'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('add-card-save')))
          .onPressed,
      isNull,
    );
    expect(cards.list(), isEmpty);
  });
}
