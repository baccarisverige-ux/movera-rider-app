import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/app/config/env.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/fee_payment/application/fee_card_payer.dart';
import 'package:movera_rider/features/fee_payment/domain/fees_payable_by_card.dart';
import 'package:movera_rider/features/profile/domain/rider_outstanding.dart';

/// Contract v0.18.136 stripeFees (DRAFT, Stripe TEST mode; owner 2026-11-20
/// "So we use stripe"): the rider pays an owed fee with the Stripe
/// PaymentSheet for the server's amount; paid is what the server says.
class FakeSheet implements FeePaymentSheet {
  FakeSheet(this.answer);
  final Future<bool> Function() answer;
  final calls = <Map<String, Object>>[];
  @override
  Future<bool> present({required String clientSecret, required String publishableKey, required String countryCode, required bool googlePay}) {
    calls.add({'secret': clientSecret, 'key': publishableKey, 'googlePay': googlePay});
    return answer();
  }
}

void main() {
  const staging = AppEnv(flavor: AppFlavor.staging, apiBaseUrl: 'https://api.example.test');
  final requests = <http.Request>[];
  late Map<String, Object?> profileAfter;
  late Object payAnswer;

  ApiClient api() {
    requests.clear();
    return ApiClient(
      env: staging,
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        final body = path.endsWith('/pay') ? payAnswer : profileAfter;
        final code = body is Map && body['code'] != null ? 409 : 200;
        return http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
      }),
    );
  }

  final owed = {
    'riderId': 'rdr_1',
    'outstandingByCurrency': [{'amountMinor': 6500, 'currency': 'SEK'}],
    'feesPayableByCard': [{'tripId': 'trp_1', 'amount': {'amountMinor': 6500, 'currency': 'SEK'}}],
  };
  const intent = {'tripId': 'trp_1', 'paymentIntentId': 'pi_1', 'amount': {'amountMinor': 6500, 'currency': 'SEK'}, 'status': 'requires_payment', 'clientSecret': 'pi_1_secret_x', 'publishableKey': 'pk_test_x', 'createdAt': '2026-11-20T10:00:00Z'};

  setUp(() {
    FeesPayableByCard.reset();
    RiderOutstanding.reset();
  });

  test('Rider.feesPayableByCard is read as the server sent it; bad rows are dropped', () {
    final list = FeesPayableByCard.fromRider({
      'feesPayableByCard': [owed['feesPayableByCard']! as List, {'tripId': '', 'amount': {'amountMinor': 1, 'currency': 'SEK'}}, {'tripId': 'x'}].expand((e) => e is List ? e : [e]).toList(),
    });
    expect(list.items.single.tripId, 'trp_1');
    expect(list.items.single.amount, const Money(6500, 'SEK'));
    expect(FeesPayableByCard.fromRider({}).items, isEmpty);
  });

  test('pay: POST /rider/fees/{tripId}/pay with no amount; the sheet gets the server secret; Google Pay is off; paid = the server says so', () async {
    payAnswer = intent;
    profileAfter = {'riderId': 'rdr_1', 'outstandingByCurrency': <Object>[]};
    final sheet = FakeSheet(() async => true);
    final outcome = await FeeCardPayer(api: api(), sheet: sheet).pay('trp_1');
    expect(outcome, FeePayOutcome.paid);
    expect(requests.first.method, 'POST');
    expect(requests.first.url.path, '/api/v1/rider/fees/trp_1/pay');
    expect(requests.first.body.contains('amount'), isFalse);
    expect(sheet.calls.single, {'secret': 'pi_1_secret_x', 'key': 'pk_test_x', 'googlePay': false});
    expect(kGooglePayEnabled, isFalse);
    expect(RiderOutstanding.current.value.owesAnything, isFalse);
  });

  test('the sheet said paid but the server still lists the fee: checking, never paid', () async {
    payAnswer = intent;
    profileAfter = owed;
    expect(await FeeCardPayer(api: api(), sheet: FakeSheet(() async => true)).pay('trp_1'), FeePayOutcome.checking);
    expect(FeesPayableByCard.current.value.forTrip('trp_1'), isNotNull);
  });

  test('closed sheet, failed sheet, server refusal (stripe_off), a live key: no payment claimed', () async {
    payAnswer = intent;
    profileAfter = owed;
    expect(await FeeCardPayer(api: api(), sheet: FakeSheet(() async => false)).pay('trp_1'), FeePayOutcome.closed);
    expect(await FeeCardPayer(api: api(), sheet: FakeSheet(() async => throw StateError('declined'))).pay('trp_1'), FeePayOutcome.failed);
    payAnswer = {'code': 'conflict', 'message': 'Card payment of fees is off here.', 'reason': 'stripe_off'};
    final sheet = FakeSheet(() async => true);
    expect(await FeeCardPayer(api: api(), sheet: sheet).pay('trp_1'), FeePayOutcome.unavailable);
    payAnswer = {...intent, 'publishableKey': 'pk_live_x'};
    expect(await FeeCardPayer(api: api(), sheet: sheet).pay('trp_1'), FeePayOutcome.unavailable);
    expect(sheet.calls, isEmpty);
  });
}
