import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/repository_authority.dart';
import 'package:movera_rider/features/wallet/domain/wallet_history.dart';
import 'package:movera_rider/features/wallet/domain/wallet_ledger.dart';

/// The rider's wallet history from the server's ledger (BQ-V41 = BQ-V20,
/// owner G12 Q5 decisions/driver-g12.md:12; owner rule R2).
///
/// `GET /api/v1/wallet/entries?limit=&cursor=` (openapi
/// `listWalletEntries`: the Cursor and Limit parameters, 1–200, default 50)
/// → `Page<WalletEntry> { items, nextCursor }`, newest first. Every
/// currency's entries are in the one list (the contract has no currency
/// filter); each amount keeps its own currency.
class ApiWalletHistory implements WalletHistorySource, ServerBackedRepository {
  ApiWalletHistory({required ApiClient api, this.limit = 50}) : _api = api;

  static const path = '/api/v1/wallet/entries';

  final ApiClient _api;
  final int limit;

  @override
  Future<WalletHistoryPage> load({String? cursor}) async {
    final query = Uri(
      queryParameters: {'limit': '$limit', 'cursor': ?cursor},
    ).query;
    final json = await _api.get('$path?$query');
    final raw = json['items'];
    final next = json['nextCursor'];
    return WalletHistoryPage(
      items: [
        if (raw is List)
          for (final item in raw)
            if (_entry(item) case final WalletHistoryEntry entry) entry,
      ],
      nextCursor: next is String && next.isNotEmpty ? next : null,
    );
  }

  /// One wire `WalletEntry`, or null when it is not one (an amount that is
  /// not Money is never guessed).
  static WalletHistoryEntry? _entry(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['entryId'];
    final kind = raw['kind'];
    final amount = Money.fromWire(raw['amount']);
    final at = raw['at'] is String ? DateTime.tryParse(raw['at']) : null;
    final trip = raw['tripId'];
    if (id is! String || kind is! String || amount == null || at == null) {
      return null;
    }
    return WalletHistoryEntry(
      id: id,
      kind: kind,
      amount: amount,
      at: at,
      tripId: trip is String ? trip : null,
    );
  }
}

/// Demo / dev builds only: the device's own ledger ([WalletLedger], the
/// demo's simulated top-ups and wallet trips) shown as one page. It is not
/// `ServerBackedRepository`; live builds compose [ApiWalletHistory].
class LedgerWalletHistory implements WalletHistorySource {
  const LedgerWalletHistory(this.ledger);

  final WalletLedger ledger;

  @override
  Future<WalletHistoryPage> load({String? cursor}) async => WalletHistoryPage(
    items: [
      for (final e in ledger.entries.reversed)
        WalletHistoryEntry(
          id: e.id,
          kind: switch (e.kind) {
            WalletEntryKind.credit => 'topup',
            WalletEntryKind.ride => 'charge',
            WalletEntryKind.refund => 'refund',
            WalletEntryKind.voucher => 'adjustment',
            WalletEntryKind.fee => 'fee',
            WalletEntryKind.debtPaid => 'debt_paid',
          },
          amount: Money(e.amountMinor, e.currency),
          at: e.at,
        ),
    ],
  );
}
