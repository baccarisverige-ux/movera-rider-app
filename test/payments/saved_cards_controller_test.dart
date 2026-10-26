import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/payments/application/saved_cards_controller.dart';
import 'package:movera_rider/features/payments/data/saved_cards_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 10, 13);

  group('CardInput', () {
    test('Luhn accepts the Visa and Mastercard test numbers', () {
      expect(CardInput.luhnValid('4242424242424242'), isTrue);
      expect(CardInput.luhnValid('5555555555554444'), isTrue);
      expect(CardInput.luhnValid('2223003122003222'), isTrue);
      expect(CardInput.luhnValid('4242424242424241'), isFalse);
      expect(CardInput.luhnValid('4242'), isFalse);
      expect(CardInput.luhnValid('42424242424242ab'), isFalse);
    });

    test('brand is detected from the first digits', () {
      expect(CardInput.detectBrand('4'), 'visa');
      expect(CardInput.detectBrand('4242424242424242'), 'visa');
      expect(CardInput.detectBrand('51'), 'mastercard');
      expect(CardInput.detectBrand('5555555555554444'), 'mastercard');
      expect(CardInput.detectBrand('2221'), 'mastercard');
      expect(CardInput.detectBrand('2720'), 'mastercard');
      expect(CardInput.detectBrand('2220'), isNull);
      expect(CardInput.detectBrand('2721'), isNull);
      expect(CardInput.detectBrand('56'), isNull);
      // Amex and Discover are not accepted.
      expect(CardInput.detectBrand('378282246310005'), isNull);
      expect(CardInput.detectBrand('6011111111111117'), isNull);
    });

    test('short prefixes stay undecided, others are rejected', () {
      expect(CardInput.brandRejected(''), isFalse);
      expect(CardInput.brandRejected('5'), isFalse);
      expect(CardInput.brandRejected('22'), isFalse);
      expect(CardInput.brandRejected('222'), isFalse);
      expect(CardInput.brandRejected('2220'), isTrue);
      expect(CardInput.brandRejected('56'), isTrue);
      expect(CardInput.brandRejected('3'), isTrue);
      expect(CardInput.brandRejected('6'), isTrue);
      expect(CardInput.brandError, 'We accept Visa and Mastercard');
    });

    test('number groups into fours and must be 16 valid digits', () {
      expect(CardInput.groupDigits('4242424242424242'), '4242 4242 4242 4242');
      expect(CardInput.groupDigits('42424'), '4242 4');
      expect(CardInput.digitsOnly('4242 4242-4242 4242'), '4242424242424242');
      expect(CardInput.numberValid('4242424242424242'), isTrue);
      expect(CardInput.numberValid('424242424242424'), isFalse);
      expect(CardInput.numberValid('6011111111111117'), isFalse);
    });

    test('expiry parses MM/YY and must be in the future', () {
      expect(CardInput.parseExpiry('08/28'), (month: 8, year: 2028));
      expect(CardInput.parseExpiry('0828'), (month: 8, year: 2028));
      expect(CardInput.parseExpiry('13/28'), isNull);
      expect(CardInput.parseExpiry('00/28'), isNull);
      expect(CardInput.parseExpiry('8/28'), isNull);
      expect(CardInput.expiryInFuture(8, 2028, now: now), isTrue);
      // Valid through the last day of the current month.
      expect(CardInput.expiryInFuture(10, 2026, now: now), isTrue);
      expect(CardInput.expiryInFuture(9, 2026, now: now), isFalse);
      expect(CardInput.expiryInFuture(12, 2025, now: now), isFalse);
    });

    test('cvc is three digits and the name is not blank', () {
      expect(CardInput.cvcValid('123'), isTrue);
      expect(CardInput.cvcValid('12'), isFalse);
      expect(CardInput.cvcValid('1234'), isFalse);
      expect(CardInput.cvcValid('12a'), isFalse);
      expect(CardInput.holderValid('Anna Berg'), isTrue);
      expect(CardInput.holderValid(' '), isFalse);
    });
  });

  group('SavedCardsController', () {
    test('add keeps only brand, last4, expiry and name', () async {
      final store = MemorySavedCardsStore();
      final cards = SavedCardsController(store: store);
      final card = await cards.add(
        number: '4242 4242 4242 4242',
        expMonth: 8,
        expYear: 2028,
        holder: ' Anna Berg ',
        now: now,
      );
      expect(card.brand, 'visa');
      expect(card.last4, '4242');
      expect(card.holder, 'Anna Berg');
      expect(card.displayName, 'Visa •••• 4242');
      expect(SavedCardsController.displayName(card), 'Visa •••• 4242');
      expect(card.expiryLabel, '08/28');
      expect(SavedCardsController.expiryLabel(card), '08/28');
      expect(card.methodBrand, 'card:${card.id}');
      expect(cards.list().single.id, card.id);
      expect(cards.hasCards, isTrue);
      expect(cards.byMethodBrand('card:${card.id}'), isNotNull);
      expect(cards.byMethodBrand('cash'), isNull);
      expect(store.cards.single.toJson().containsKey('number'), isFalse);
      expect(store.cards.single.toJson().containsKey('cvc'), isFalse);
    });

    test('mastercard is named Mastercard', () async {
      final cards = SavedCardsController(store: MemorySavedCardsStore());
      final card = await cards.add(
        number: '5555555555554444',
        expMonth: 1,
        expYear: 2030,
        holder: 'Erik',
        now: now,
      );
      expect(card.brand, 'mastercard');
      expect(card.displayName, 'Mastercard •••• 4444');
      expect(card.expiryLabel, '01/30');
    });

    test('add rejects other brands, bad checksums and expired cards', () {
      final cards = SavedCardsController(store: MemorySavedCardsStore());
      expect(
        () => cards.add(
          number: '6011111111111117',
          expMonth: 8,
          expYear: 2028,
          holder: 'Anna',
          now: now,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'We accept Visa and Mastercard',
          ),
        ),
      );
      expect(
        () => cards.add(
          number: '4242424242424241',
          expMonth: 8,
          expYear: 2028,
          holder: 'Anna',
          now: now,
        ),
        throwsArgumentError,
      );
      expect(
        () => cards.add(
          number: '4242424242424242',
          expMonth: 9,
          expYear: 2026,
          holder: 'Anna',
          now: now,
        ),
        throwsArgumentError,
      );
      expect(
        () => cards.add(
          number: '4242424242424242',
          expMonth: 8,
          expYear: 2028,
          holder: ' ',
          now: now,
        ),
        throwsArgumentError,
      );
      expect(cards.list(), isEmpty);
    });

    test('remove drops the card and notifies', () async {
      final store = MemorySavedCardsStore();
      final cards = SavedCardsController(store: store);
      var notified = 0;
      cards.addListener(() => notified++);
      final a = await cards.add(
        number: '4242424242424242',
        expMonth: 8,
        expYear: 2028,
        holder: 'Anna',
        now: now,
      );
      final b = await cards.add(
        number: '5555555555554444',
        expMonth: 8,
        expYear: 2028,
        holder: 'Anna',
        now: now,
      );
      expect(cards.list().length, 2);
      await cards.remove(a.id);
      expect(cards.list().map((c) => c.id), [b.id]);
      expect(store.cards.map((c) => c.id), [b.id]);
      await cards.remove('missing');
      expect(cards.list().length, 1);
      expect(notified, greaterThanOrEqualTo(3));
    });

    test(
      'cards persist across controller instances (SharedPreferences)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final first = SavedCardsController();
        final card = await first.add(
          number: '4242424242424242',
          expMonth: 8,
          expYear: 2028,
          holder: 'Anna Berg',
          now: now,
        );

        final second = SavedCardsController();
        expect(second.list(), isEmpty);
        await second.load();
        expect(second.list().single.id, card.id);
        expect(second.list().single.displayName, 'Visa •••• 4242');
        expect(second.list().single.expiryLabel, '08/28');
        expect(second.list().single.holder, 'Anna Berg');

        await second.remove(card.id);
        final third = SavedCardsController();
        await third.load();
        expect(third.list(), isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(PrefsSavedCardsStore.key), isNull);
      },
    );

    test('a corrupt store reads as no cards', () async {
      SharedPreferences.setMockInitialValues({
        PrefsSavedCardsStore.key: 'not json',
      });
      final cards = SavedCardsController();
      await cards.load();
      expect(cards.list(), isEmpty);
    });
  });
}
