import 'package:movera_rider/l10n/l10n.dart';

/// A ride payment method's name as the rider reads it. The stored name
/// ("Cash") stays the method's identity; only what is shown is translated.
String paymentNameFor(String brand, String name) => switch (brand) {
  'cash' => L10n.current.payCash,
  'cards' => L10n.current.payCard,
  'wallet' => L10n.current.moveraWallet,
  _ => name,
};

/// The line under a payment method: the built-in English lines are
/// translated, anything else (a card's expiry, a server text) is shown as is.
String paymentDetailFor(String brand, String detail) => switch (detail) {
  'Pay the driver in cash' => L10n.current.payDriverCash,
  'Pay from your balance' => L10n.current.payFromBalance,
  'Pays when the search starts' => L10n.current.paysWhenSearchStarts,
  _ => detail,
};
