class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.amountMinor,
    required this.currency,
  });
  final String id;
  final int amountMinor;
  final String currency;
}

/// What a payment intent pays for, so the server knows what to credit or
/// settle when it is captured (ARCH-6, contract C-10, PROPOSED).
enum PaymentPurpose {
  walletTopUp('wallet_topup'),
  ride('ride'),
  tip('tip');

  const PaymentPurpose(this.wire);

  /// The value sent as `purpose` on `POST /api/v1/payments`.
  final String wire;
}

abstract class PaymentGateway {
  Future<PaymentIntent> create({
    required int amountMinor,
    required String currency,
    required String idempotencyKey,
    PaymentPurpose? purpose,
    String? rideId,
  });
  Future<String> confirm(String intentId);
  Future<String> status(String intentId);
}
