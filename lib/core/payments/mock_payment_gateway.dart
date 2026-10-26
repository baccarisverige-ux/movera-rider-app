import 'package:movera_rider/core/payments/payment_gateway.dart';
import 'package:movera_rider/core/utils/request_id.dart';

class MockPaymentGateway implements PaymentGateway {
  final Map<String, PaymentIntent> _intents = {};

  /// The intent created for each idempotency key (rider-u242: a reused key
  /// answers its own intent, not the newest one of any key).
  final Map<String, PaymentIntent> _byKey = {};
  bool failNext = false;

  @override
  Future<PaymentIntent> create({
    required int amountMinor,
    required String currency,
    required String idempotencyKey,
    PaymentPurpose? purpose,
    String? rideId,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('payment_failed');
    }
    final replay = _byKey[idempotencyKey];
    if (replay != null) return replay;
    final intent = PaymentIntent(
      id: 'pi_${newRequestId()}',
      amountMinor: amountMinor,
      currency: currency,
    );
    _intents[intent.id] = intent;
    _byKey[idempotencyKey] = intent;
    return intent;
  }

  @override
  Future<String> confirm(String intentId) async => 'succeeded';

  @override
  Future<String> status(String intentId) async =>
      _intents.containsKey(intentId) ? 'succeeded' : 'not_found';
}
