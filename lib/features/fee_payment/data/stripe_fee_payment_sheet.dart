import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:movera_rider/features/fee_payment/application/fee_card_payer.dart';

/// The real flutter_stripe PaymentSheet (Stripe TEST mode only: the server
/// sends a pk_test_ key; FeeCardPayer refuses any other). Card and Apple Pay;
/// Google Pay only when kGooglePayEnabled (default OFF, not approved yet).
class StripeFeePaymentSheet implements FeePaymentSheet {
  const StripeFeePaymentSheet();

  /// Apple Pay merchant id (not a secret; the Apple Pay entitlement is a release step).
  static const merchantIdentifier = 'merchant.com.movera.rider';

  @override
  Future<bool> present({
    required String clientSecret,
    required String publishableKey,
    required String countryCode,
    required bool googlePay,
  }) async {
    Stripe.publishableKey = publishableKey;
    Stripe.merchantIdentifier = merchantIdentifier;
    await Stripe.instance.applySettings();
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'Movera',
        applePay: PaymentSheetApplePay(merchantCountryCode: countryCode),
        googlePay: googlePay
            ? PaymentSheetGooglePay(
                merchantCountryCode: countryCode,
                testEnv: true,
              )
            : null,
      ),
    );
    try {
      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return false;
      rethrow;
    }
  }
}
