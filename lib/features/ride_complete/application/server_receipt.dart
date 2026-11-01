import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/logging/app_log.dart';

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
  });

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
    final refunded = Money.fromWire(json['refunded']);
    return ServerReceipt(
      endedEarly: json['endedEarly'] == true,
      endedBy: by is String ? by : null,
      tip: tip is Map ? Money.fromWire(tip['amount']) : null,
      debtIncluded: Money.fromWire(json['debtIncluded']),
      refunded: refunded != null && refunded.amountMinor > 0 ? refunded : null,
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
