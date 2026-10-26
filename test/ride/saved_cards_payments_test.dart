import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/data/default_payment_store.dart';
import 'package:movera_rider/features/payments/data/saved_cards_store.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';

void main() {
  const visa = SavedCard(
    id: 'c1',
    brand: 'visa',
    last4: '4242',
    expMonth: 8,
    expYear: 2028,
    holder: 'Anna Berg',
  );
  const master = SavedCard(
    id: 'c2',
    brand: 'mastercard',
    last4: '4444',
    expMonth: 1,
    expYear: 2030,
    holder: 'Anna Berg',
  );

  test('payments() lists saved cards in place of the generic Card', () async {
    final cards = SavedCardsController(
      store: MemorySavedCardsStore([visa, master]),
    );
    final selection = RideSelectionController(savedCards: cards);
    // Before loading: no cards yet, so the generic Card row.
    expect(selection.hasSavedCard, isFalse);
    expect(selection.payments().map((p) => p.brand), [
      'google',
      'cards',
      'cash',
    ]);

    await selection.loadSavedCards();
    expect(selection.hasSavedCard, isTrue);
    final items = selection.payments();
    expect(items.map((p) => p.brand), ['google', 'card:c1', 'card:c2', 'cash']);
    expect(items[1].name, 'Visa •••• 4242');
    expect(items[1].detail, 'Expires 08/28');
    expect(items[2].name, 'Mastercard •••• 4444');
    expect(items[2].detail, 'Expires 01/30');
    expect(selection.savedCardFor('card:c2')?.brand, 'mastercard');
    expect(selection.savedCardFor('cards'), isNull);
  });

  test(
    'a saved card can be chosen by name and is the booking method',
    () async {
      final cards = SavedCardsController(store: MemorySavedCardsStore([visa]));
      final memory = MemoryDefaultPaymentStore();
      final selection = RideSelectionController(
        savedCards: cards,
        paymentStore: memory,
      );
      await selection.loadSavedCards();

      selection.selectPaymentNamed('Visa •••• 4242');
      expect(selection.selectedPaymentItem()?.brand, 'card:c1');

      selection.selectPayment(
        selection.payments().indexWhere((p) => p.brand == 'card:c1'),
      );
      expect(memory.value, 'card:c1');

      // The remembered default comes back as the same card.
      final again = RideSelectionController(
        savedCards: cards,
        paymentStore: memory,
      );
      await again.loadSavedCards();
      await again.restoreDefaultPayment();
      expect(again.selectedPaymentItem()?.brand, 'card:c1');
    },
  );

  test('removing the chosen card falls back to a valid method', () async {
    final cards = SavedCardsController(store: MemorySavedCardsStore([visa]));
    final selection = RideSelectionController(savedCards: cards);
    await selection.loadSavedCards();
    selection.selectPaymentByBrand('card:c1');
    expect(selection.selectedPaymentItem()?.brand, 'card:c1');

    await cards.remove('c1');
    expect(selection.hasSavedCard, isFalse);
    expect(selection.payments().map((p) => p.brand), [
      'google',
      'cards',
      'cash',
    ]);
    expect(selection.selectedPaymentItem(), isNotNull);
  });
}
