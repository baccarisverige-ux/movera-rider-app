import 'package:movera_rider/core/contracts/money.dart';

/// Where a refund may go (openapi `RefundDestination`). Only these three are
/// in the contract today: a refund back to a card or Apple Pay waits for the
/// card company (contract.json#debtModel.refunds, Q-M4), so the app offers
/// nothing the server does not list in `RiderRefund.choices`.
enum RefundChoice {
  wallet,
  swish,
  bank;

  String get wire => name;

  static RefundChoice? fromWire(Object? raw) => switch (raw) {
    'wallet' => RefundChoice.wallet,
    'swish' => RefundChoice.swish,
    'bank' => RefundChoice.bank,
    _ => null,
  };
}

/// The rider's view of one refund (openapi `RiderRefund`, served by
/// GET /rider/refunds and answered by POST /rider/refunds/{id}/destination).
///
/// BQ-V39 (owner Q-M4, decisions/session-2026-11-06.md:1102): a refund
/// starts with `destination: null`; while it is null the rider chooses one
/// of [choices]. The [amount] is the server's Money: the app shows it with
/// its currency's decimals and never works it out.
class RiderRefund {
  const RiderRefund({
    required this.refundId,
    required this.tripId,
    required this.amount,
    required this.reason,
    required this.status,
    this.destination,
    this.payoutStatus,
    this.payoutTo,
    this.choices = const <RefundChoice>[],
  });

  final String refundId;
  final String tripId;
  final Money amount;
  final String reason;
  final String status;

  /// `wallet`, `swish` or `bank`; null until the rider chooses.
  final String? destination;

  /// Swish / bank only: `pending` until an admin marks it paid, then `paid`.
  final String? payoutStatus;

  /// The server's masked account ("Swish ••4567", "Bank ••1234").
  final String? payoutTo;

  /// What the server lets the rider choose, in the server's order. A value
  /// this app does not know is left out (never shown, never sent).
  final List<RefundChoice> choices;

  /// The refund still needs the rider's choice.
  bool get waiting => destination == null && choices.isNotEmpty;

  /// Which bank form the server takes (RefundDestinationCommand.bank: "SE:
  /// clearing + account number; other countries: IBAN"). `RiderRefund`
  /// carries no country; the contract's own choices say it: Swish is offered
  /// only in Sweden ("SE wallet, swish, bank; FR wallet, bank"), and a
  /// Swedish trip is paid in SEK. A wrong guess is refused by the server
  /// (400 bank_details_invalid), never applied.
  bool get swedishBank =>
      choices.contains(RefundChoice.swish) || amount.currency == 'SEK';

  static RiderRefund? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['refundId'];
    final trip = raw['tripId'];
    final amount = Money.fromWire(raw['amount']);
    if (id is! String || id.isEmpty || trip is! String || amount == null) {
      return null;
    }
    final destination = raw['destination'];
    final payoutStatus = raw['payoutStatus'];
    final payoutTo = raw['payoutTo'];
    final choices = <RefundChoice>[];
    final rawChoices = raw['choices'];
    if (rawChoices is List) {
      for (final item in rawChoices) {
        final choice = RefundChoice.fromWire(item);
        if (choice != null && !choices.contains(choice)) choices.add(choice);
      }
    }
    return RiderRefund(
      refundId: id,
      tripId: trip,
      amount: amount,
      reason: raw['reason']?.toString() ?? '',
      status: raw['status']?.toString() ?? '',
      destination: destination is String && destination.isNotEmpty
          ? destination
          : null,
      payoutStatus: payoutStatus is String ? payoutStatus : null,
      payoutTo: payoutTo is String ? payoutTo : null,
      choices: choices,
    );
  }
}

/// The body of POST /rider/refunds/{refundId}/destination
/// (openapi `RefundDestinationCommand`).
class RefundDestinationChoice {
  const RefundDestinationChoice.wallet()
    : method = RefundChoice.wallet,
      _details = const <String, Object?>{};

  /// A Swedish mobile number, +46 then 7 to 10 digits.
  RefundDestinationChoice.swish({required String phone})
    : method = RefundChoice.swish,
      _details = {
        'swish': {'phone': phone},
      };

  /// `SwedishBankAccount`.
  RefundDestinationChoice.swedishBank({
    required String clearingNumber,
    required String accountNumber,
    required String holderName,
  }) : method = RefundChoice.bank,
       _details = {
         'bank': {
           'clearingNumber': clearingNumber,
           'accountNumber': accountNumber,
           'holderName': holderName,
         },
       };

  /// `IbanBankAccount` (spaces allowed; the server stores it without).
  RefundDestinationChoice.iban({
    required String iban,
    String? bic,
    required String holderName,
  }) : method = RefundChoice.bank,
       _details = {
         'bank': {
           'iban': iban,
           if (bic != null && bic.isNotEmpty) 'bic': bic,
           'holderName': holderName,
         },
       };

  final RefundChoice method;
  final Map<String, Object?> _details;

  Map<String, Object?> toWire() => {'method': method.wire, ..._details};

  /// The contract's patterns, checked before sending so a typo is shown on
  /// the field instead of a 400.
  static final swishPhone = RegExp(r'^\+46\d{7,10}$');
  static final clearingNumber = RegExp(r'^\d{4,5}$');
  static final accountNumber = RegExp(r'^\d{6,12}$');
  static final bic = RegExp(r'^[A-Z0-9]{8}([A-Z0-9]{3})?$');

  /// IbanBankAccount: the server takes it upper case without spaces.
  static final ibanPattern = RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{10,30}$');

  static bool validHolder(String name) {
    final n = name.trim().length;
    return n >= 2 && n <= 120;
  }

  static bool validIban(String raw) =>
      ibanPattern.hasMatch(raw.replaceAll(RegExp(r'\s+'), '').toUpperCase());
}
