import 'package:flutter/foundation.dart';
import 'package:movera_rider/features/payments/data/saved_cards_store.dart';
import 'package:movera_rider/features/payments/domain/saved_card.dart';

export 'package:movera_rider/features/payments/domain/saved_card.dart';

/// Card-number rules shared by the Add card form and its tests.
class CardInput {
  const CardInput._();

  static String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  /// "4242424242424242" -> "4242 4242 4242 4242".
  static String groupDigits(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Luhn checksum over a digit string (false when fewer than 12 digits).
  static bool luhnValid(String digits) {
    if (digits.length < 12 || !RegExp(r'^\d+$').hasMatch(digits)) return false;
    var sum = 0;
    var doubleIt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var d = digits.codeUnitAt(i) - 48;
      if (doubleIt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      doubleIt = !doubleIt;
    }
    return sum % 10 == 0;
  }

  /// 'visa' (4…), 'mastercard' (51–55, 2221–2720) or null.
  static String? detectBrand(String digits) {
    if (digits.isEmpty) return null;
    if (digits.startsWith('4')) return 'visa';
    if (digits.length >= 2) {
      final two = int.tryParse(digits.substring(0, 2));
      if (two != null && two >= 51 && two <= 55) return 'mastercard';
    }
    if (digits.length >= 4) {
      final four = int.tryParse(digits.substring(0, 4));
      if (four != null && four >= 2221 && four <= 2720) return 'mastercard';
    }
    return null;
  }

  /// True once enough digits are typed to know the card is neither Visa
  /// nor Mastercard. Short prefixes ("5", "22") are still undecided.
  static bool brandRejected(String digits) {
    if (digits.isEmpty) return false;
    if (detectBrand(digits) != null) return false;
    final first = digits[0];
    if (first == '4') return false;
    if (first == '5') return digits.length >= 2;
    if (first == '2') return digits.length >= 4;
    return true;
  }

  /// Developer text of the [ArgumentError] [SavedCardsController.add]
  /// throws; riders read l10n's cardBrandsAccepted (rider-52).
  static const String brandError = 'We accept Visa and Mastercard';

  /// Whole number: 16 digits, accepted brand, Luhn-valid.
  static bool numberValid(String digits) =>
      digits.length == 16 && detectBrand(digits) != null && luhnValid(digits);

  /// Expiry "MM/YY" -> (month, fullYear), or null when malformed.
  static ({int month, int year})? parseExpiry(String raw) {
    final digits = digitsOnly(raw);
    if (digits.length != 4) return null;
    final month = int.parse(digits.substring(0, 2));
    final year = 2000 + int.parse(digits.substring(2, 4));
    if (month < 1 || month > 12) return null;
    return (month: month, year: year);
  }

  /// A card is usable through the last day of its expiry month.
  static bool expiryInFuture(int month, int year, {DateTime? now}) {
    final today = now ?? DateTime.now();
    if (year > today.year) return true;
    if (year < today.year) return false;
    return month >= today.month;
  }

  static bool cvcValid(String raw) => RegExp(r'^\d{3}$').hasMatch(raw);

  static bool holderValid(String raw) => raw.trim().length >= 2;
}

/// The rider's saved cards (demo: stored on this device). The list is
/// cached so [list] is synchronous for ride selection; call [load] once.
class SavedCardsController extends ChangeNotifier {
  SavedCardsController({SavedCardsStore? store})
    : _store = store ?? const PrefsSavedCardsStore();

  final SavedCardsStore _store;
  List<SavedCard> _cards = const [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    _cards = await _store.read();
    _loaded = true;
    notifyListeners();
  }

  /// Forgets the signed-out rider's cards in memory.
  void clearLocal() {
    _cards = const [];
    _loaded = false;
    notifyListeners();
  }

  List<SavedCard> list() => List.unmodifiable(_cards);

  bool get hasCards => _cards.isNotEmpty;

  SavedCard? byId(String id) {
    for (final card in _cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  /// The card behind a `card:<id>` payment brand, or null.
  SavedCard? byMethodBrand(String brand) {
    if (!brand.startsWith('card:')) return null;
    return byId(brand.substring('card:'.length));
  }

  static String displayName(SavedCard card) => card.displayName;
  static String expiryLabel(SavedCard card) => card.expiryLabel;

  /// Validates and saves a card. Only brand, last4, expiry and holder are
  /// kept. Throws [ArgumentError] when the details are not valid.
  Future<SavedCard> add({
    required String number,
    required int expMonth,
    required int expYear,
    required String holder,
    DateTime? now,
    String? id,
  }) async {
    final digits = CardInput.digitsOnly(number);
    final brand = CardInput.detectBrand(digits);
    if (brand == null) throw ArgumentError(CardInput.brandError);
    if (!CardInput.numberValid(digits)) {
      throw ArgumentError('Check the card number');
    }
    if (expMonth < 1 || expMonth > 12) throw ArgumentError('Check the expiry');
    if (!CardInput.expiryInFuture(expMonth, expYear, now: now)) {
      throw ArgumentError('This card has expired');
    }
    if (!CardInput.holderValid(holder)) {
      throw ArgumentError('Enter the name on the card');
    }
    if (!_loaded) await load();
    final card = SavedCard(
      id: id ?? 'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      brand: brand,
      last4: digits.substring(digits.length - 4),
      expMonth: expMonth,
      expYear: expYear,
      holder: holder.trim(),
    );
    // Stored first: a store that refuses (saved cards switched off in a
    // release build, ARCH-7) must not leave the card listed in memory.
    final next = [..._cards, card];
    await _store.write(next);
    _cards = next;
    notifyListeners();
    return card;
  }

  Future<void> remove(String id) async {
    if (!_loaded) await load();
    final next = _cards.where((c) => c.id != id).toList();
    if (next.length == _cards.length) return;
    _cards = next;
    await _store.write(_cards);
    notifyListeners();
  }
}
