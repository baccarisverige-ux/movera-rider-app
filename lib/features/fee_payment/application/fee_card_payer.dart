import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/fee_payment/domain/fees_payable_by_card.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';

/// Google Pay is NOT approved by the owner yet (2026-11-20): off unless the
/// build sets `--dart-define=MOVERA_GOOGLE_PAY=true`. Card and Apple Pay only.
const bool kGooglePayEnabled = bool.fromEnvironment('MOVERA_GOOGLE_PAY');

/// The Stripe PaymentSheet behind a port, so tests need no plugin.
abstract class FeePaymentSheet {
  /// Shows the sheet for the server's PaymentIntent. true = the rider paid
  /// (Stripe said so on the phone); false = she closed it. Throws on a failure.
  Future<bool> present({required String clientSecret, required String publishableKey, required String countryCode, required bool googlePay});
}

enum FeePayOutcome { paid, checking, closed, failed, unavailable }

/// Contract v0.18.136 `stripeFees` (DRAFT): POST /rider/fees/{tripId}/pay
/// makes (or returns) the one PaymentIntent for the server's amount; the
/// PaymentSheet takes the card or Apple Pay; the fee is paid only when the
/// SERVER says so (its signed webhook), read back from GET /rider/profile.
class FeeCardPayer {
  FeeCardPayer({required ApiClient api, required FeePaymentSheet sheet}) : _api = api, _sheet = sheet;
  final ApiClient _api;
  final FeePaymentSheet _sheet;

  static const _profilePath = '/api/v1/rider/profile';

  Future<FeePayOutcome> pay(String tripId, {String countryCode = 'SE'}) async {
    final Map<String, dynamic> intent;
    try {
      intent = await _api.post('/api/v1/rider/fees/${Uri.encodeComponent(tripId)}/pay', body: const {});
    } on ApiError {
      await refresh();
      return FeePayOutcome.unavailable;
    }
    final secret = intent['clientSecret'];
    final key = intent['publishableKey'];
    if (secret is! String || key is! String || !key.startsWith('pk_test_')) {
      await refresh();
      return FeePayOutcome.unavailable;
    }
    final bool done;
    try {
      done = await _sheet.present(clientSecret: secret, publishableKey: key, countryCode: countryCode, googlePay: kGooglePayEnabled);
    } catch (_) {
      return FeePayOutcome.failed;
    }
    if (!done) return FeePayOutcome.closed;
    await refresh();
    return FeesPayableByCard.current.value.forTrip(tripId) == null ? FeePayOutcome.paid : FeePayOutcome.checking;
  }

  /// Reads the Rider again: what she owes and can pay comes from the server only.
  Future<void> refresh() async {
    try {
      final rider = await _api.get(_profilePath);
      RiderOutstanding.current.value = RiderOutstanding.fromRider(rider);
      FeesPayableByCard.current.value = FeesPayableByCard.fromRider(rider);
    } catch (_) {
      // The next profile read updates them.
    }
  }
}
