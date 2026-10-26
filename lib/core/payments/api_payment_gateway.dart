import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/payments/payment_gateway.dart';

class ApiPaymentGateway implements PaymentGateway {
  ApiPaymentGateway({required ApiClient api}) : _api = api;

  final ApiClient _api;

  @override
  Future<PaymentIntent> create({
    required int amountMinor,
    required String currency,
    required String idempotencyKey,
    PaymentPurpose? purpose,
    String? rideId,
  }) async {
    if (amountMinor <= 0) {
      throw const PaymentTransportException('Payment amount must be positive.');
    }
    final normalizedCurrency = currency.trim().toUpperCase();
    final key = idempotencyKey.trim();
    if (normalizedCurrency.isEmpty || key.isEmpty) {
      throw const PaymentTransportException(
        'Payment currency and idempotency key are required.',
      );
    }

    final Map<String, dynamic> response;
    try {
      response = await _api.post(
        '/api/v1/payments',
        body: {
          'amountMinor': amountMinor,
          'currency': normalizedCurrency,
          // C-10 (PROPOSED): tells the server what to credit on capture.
          if (purpose != null) 'purpose': purpose.wire,
          if (rideId != null && rideId.trim().isNotEmpty)
            'rideId': rideId.trim(),
        },
        idempotencyKey: key,
      );
    } on ApiError catch (error) {
      // Contract §1: the server refuses a key reused with another body
      // (409). That payment is not this one: fail closed.
      if (error.statusCode == 409) {
        throw const PaymentTransportException(
          'Payment idempotency key was already used for another payment.',
        );
      }
      rethrow;
    }
    final intent = response['intent'];
    if (response['code'] != 'OK' || intent is! Map) {
      throw const PaymentTransportException(
        'Payment intent creation was not acknowledged.',
      );
    }

    final data = Map<String, dynamic>.from(intent);
    final id = data['id'];
    final returnedAmount = data['amountMinor'];
    final returnedCurrency = data['currency'];
    if (id is! String ||
        id.trim().isEmpty ||
        returnedAmount is! num ||
        returnedAmount.round() != amountMinor ||
        returnedCurrency is! String ||
        returnedCurrency.toUpperCase() != normalizedCurrency) {
      throw const PaymentTransportException(
        'Payment intent response did not match the request.',
      );
    }

    return PaymentIntent(
      id: id.trim(),
      amountMinor: returnedAmount.round(),
      currency: returnedCurrency.toUpperCase(),
    );
  }

  @override
  Future<String> confirm(String intentId) async {
    final id = _normalizedIntentId(intentId);
    final response = await _api.post('/api/v1/payments/$id/confirm');
    return _readStatus(response, operation: 'confirmation');
  }

  @override
  Future<String> status(String intentId) async {
    final id = _normalizedIntentId(intentId);
    final response = await _api.get('/api/v1/payments/$id');
    return _readStatus(response, operation: 'status');
  }

  String _normalizedIntentId(String value) {
    final id = value.trim();
    if (id.isEmpty || id.contains('/')) {
      throw const PaymentTransportException('Invalid payment intent id.');
    }
    return id;
  }

  String _readStatus(
    Map<String, dynamic> response, {
    required String operation,
  }) {
    final raw =
        response['status'] ??
        (response['intent'] is Map
            ? (response['intent'] as Map)['status']
            : null);
    if (response['code'] != 'OK' || raw is! String || raw.trim().isEmpty) {
      throw PaymentTransportException(
        'Payment $operation was not acknowledged.',
      );
    }

    const allowed = {
      'requires_confirmation',
      'processing',
      'succeeded',
      'failed',
      'refunded',
      'partially_refunded',
      'cancelled',
    };
    final status = raw.trim().toLowerCase();
    if (!allowed.contains(status)) {
      throw PaymentTransportException(
        'Payment $operation returned an unknown status.',
      );
    }
    return status;
  }
}

class PaymentTransportException implements Exception {
  const PaymentTransportException(this.message);

  final String message;

  @override
  String toString() => 'PaymentTransportException($message)';
}
