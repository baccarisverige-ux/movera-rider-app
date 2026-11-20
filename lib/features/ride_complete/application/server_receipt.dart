import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/logging/app_log.dart';

/// One line of the server's receipt (`Receipt.fareLines`, "the rider's
/// lines"): its code (contract.json#fareLines.rider) and its amount.
class ReceiptFareLine {
  const ReceiptFareLine(this.code, this.amount);

  final String code;
  final Money amount;
}

/// The parts of the server's receipt (contract v0.18.10 `finish.receipt`,
/// `GET /trips/{tripId}/receipt`) the trip details add: "Avslutad i förtid"
/// with who ended it, an earlier unpaid fee, the tip and refunds.
class ServerReceipt {
  const ServerReceipt({
    this.endedEarly = false,
    this.endedBy,
    this.tip,
    this.debtIncluded,
    this.refunded,
    this.total,
    this.cashPaid,
    this.paymentMethod,
    this.fareLines = const <ReceiptFareLine>[],
  });

  /// R6 (owner 2026-11-20): the receipt's `fareLines`, as the server sent
  /// them and in its order, lines of 0 left out. The app shows each line
  /// with its amount and adds nothing up. Empty when the server sent none
  /// or when any line could not be read (never half a list).
  final List<ReceiptFareLine> fareLines;

  static List<ReceiptFareLine> _fareLines(Object? raw, Money? total) {
    if (raw is! List) return const <ReceiptFareLine>[];
    final lines = <ReceiptFareLine>[];
    for (final item in raw) {
      if (item is! Map) return const <ReceiptFareLine>[];
      final code = item['code'];
      final amount = Money.fromWire(item['amount']);
      if (code is! String || code.trim().isEmpty || amount == null) {
        return const <ReceiptFareLine>[];
      }
      // One receipt, one currency: a line in another one is not shown.
      if (total != null && amount.currency != total.currency) {
        return const <ReceiptFareLine>[];
      }
      if (amount.amountMinor == 0) continue;
      lines.add(ReceiptFareLine(code.trim(), amount));
    }
    return List.unmodifiable(lines);
  }

  /// G33 (contract v0.18.78 `finish.payInCarLine`): the receipt's
  /// `cashPaid`, what the rider paid the driver in the car; after a reload
  /// the summary's pay-in-car line takes its amount from here.
  final Money? cashPaid;

  /// The receipt's `paymentMethod` (`cash | card | apple_pay | wallet`).
  final String? paymentMethod;

  /// The receipt's `total` (what the rider paid for the trip), so History
  /// shows the server's receipt, not the phone's copy (live sweep M-11).
  final Money? total;

  final bool endedEarly;

  /// `rider | driver`.
  final String? endedBy;
  final Money? tip;
  final Money? debtIncluded;
  final Money? refunded;

  static ServerReceipt? tryParse(Map<String, dynamic> json) {
    if (json['tripId'] is! String) return null;
    final tip = json['tip'];
    final by = json['endedBy'];
    final method = json['paymentMethod'];
    final refunded = Money.fromWire(json['refunded']);
    final total = Money.fromWire(json['total']);
    return ServerReceipt(
      fareLines: _fareLines(json['fareLines'], total),
      endedEarly: json['endedEarly'] == true,
      endedBy: by is String ? by : null,
      tip: tip is Map ? Money.fromWire(tip['amount']) : null,
      debtIncluded: Money.fromWire(json['debtIncluded']),
      refunded: refunded != null && refunded.amountMinor > 0 ? refunded : null,
      total: total,
      cashPaid: Money.fromWire(json['cashPaid']),
      paymentMethod: method is String ? method : null,
    );
  }

  /// Reads the receipt; null when there is none yet (`receipt_not_ready`),
  /// on the mock transport, or on any failure (the local details stay).
  static Future<ServerReceipt?> load(String tripId, {ApiClient? api}) async {
    final client = api ?? AppScope.instance.api;
    if (!client.contractWire || tripId.trim().isEmpty) return null;
    try {
      return tryParse(await client.get(client.tripPath(tripId, 'receipt')));
    } catch (error) {
      AppLog.warning(
        'ride.receipt.not_read',
        extra: {'rideId': tripId, 'error': '$error'},
      );
      return null;
    }
  }
}
