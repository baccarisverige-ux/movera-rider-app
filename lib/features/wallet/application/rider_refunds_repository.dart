import 'dart:convert';

import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/features/wallet/domain/rider_refund.dart';

/// BQ-V39 (contract.json#debtModel.refunds, owner Q-M4): the rider's refunds
/// and his one choice of where each goes.
///
/// * `GET /rider/refunds` → `RiderRefundPage { items: [RiderRefund] }`
///   (the newest 100).
/// * `POST /rider/refunds/{refundId}/destination` with an Idempotency-Key →
///   `RiderRefund`. Errors: 404 refund_not_found, 409 destination_chosen,
///   400 method_not_available / bank_details_invalid.
class RiderRefundsRepository {
  RiderRefundsRepository({ApiClient? api})
    : _api = api ?? AppScope.instance.api;

  final ApiClient _api;

  static const path = '/api/v1/rider/refunds';

  /// Served by movera-server only (not by the demo transport).
  bool get available => _api.contractWire;

  Future<List<RiderRefund>> list() async {
    if (!available) return const <RiderRefund>[];
    final page = await _api.get(path);
    return [
      for (final item in (page['items'] as List? ?? const []))
        if (RiderRefund.fromWire(item) case final RiderRefund refund) refund,
    ];
  }

  /// The refunds that still wait for the rider's choice (of [tripId] only,
  /// when given), newest first as the server sends them.
  Future<List<RiderRefund>> waiting({String? tripId}) async => [
    for (final refund in await list())
      if (refund.waiting && (tripId == null || refund.tripId == tripId)) refund,
  ];

  /// The rider's choice. The key is derived from the refund and the exact
  /// body (the route-change refund's pattern, `stableIdempotencyKey`): a
  /// retry after a lost answer is the same request, so the money is never
  /// sent twice; another choice is another request.
  Future<RiderRefund> choose(
    String refundId,
    RefundDestinationChoice choice,
  ) async {
    final body = choice.toWire();
    final answer = await _api.post(
      '$path/${Uri.encodeComponent(refundId)}/destination',
      body: body,
      idempotencyKey: stableIdempotencyKey(
        'refund-destination',
        '$refundId|${jsonEncode(body)}',
      ),
    );
    final refund = RiderRefund.fromWire(answer);
    if (refund == null) {
      throw const FormatException('RiderRefund expected');
    }
    return refund;
  }
}
