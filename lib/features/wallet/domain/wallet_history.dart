import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// One line of the rider's wallet history, as the server's ledger holds it
/// (contract `WalletEntry { entryId, ownerId, amount: Money, kind, tripId?,
/// at }`; BQ-V41 = BQ-V20, owner G12 Q5 decisions/driver-g12.md:12). The
/// app shows [amount] exactly as sent (owner rule R2: the apps never work
/// money out): positive money came in, negative went out.
class WalletHistoryEntry {
  const WalletHistoryEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.at,
    this.tripId,
  });

  final String id;

  /// The server's kind: topup, charge, refund, payout, adjustment, fee,
  /// debt_paid (contract v0.18.84). A kind this app does not know yet keeps
  /// its line, with the general label.
  final String kind;
  final Money amount;
  final DateTime at;
  final String? tripId;
}

/// One page of the history (contract `Page<WalletEntry>`): [nextCursor] is
/// the server's opaque cursor of the next page, null on the last one.
class WalletHistoryPage {
  const WalletHistoryPage({required this.items, this.nextCursor});

  final List<WalletHistoryEntry> items;
  final String? nextCursor;
}

/// Where the history comes from: the server on live
/// (`ApiWalletHistory`, GET /wallet/entries), the device's demo ledger in
/// demo / dev builds.
abstract interface class WalletHistorySource {
  /// The page after [cursor] (the first page when null), newest first.
  Future<WalletHistoryPage> load({String? cursor});
}

/// The rider's words for a server [kind] (sv / fr / en). adjustment is the
/// admin's Add money to wallet (and an admin correction):
/// contract.json#walletCredit.riderText.historyLabel "Credit from Movera";
/// fee and debt_paid are contract.json#debtModel.texts walletFee and
/// walletDebtPaid.
String walletEntryLabel(String kind, AppLocalizations l10n) => switch (kind) {
  'adjustment' => l10n.walletEntryCreditFromMovera,
  'refund' => l10n.walletEntryRefund,
  'charge' => l10n.walletEntryTripPayment,
  'topup' => l10n.walletEntryTopUp,
  'payout' => l10n.walletEntryPayout,
  'fee' => l10n.walletEntryFee,
  'debt_paid' => l10n.walletEntryDebtPaid,
  _ => l10n.walletEntryOther,
};
