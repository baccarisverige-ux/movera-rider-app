import 'package:movera_rider/features/wallet/domain/wallet_ledger.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// The row label of a wallet movement, or null where the app has none yet
/// (it shows no wallet history list today). J10 (contract v0.18.84
/// `debtModel.texts`): the new kinds `fee` ("Unpaid fee") and `debt_paid`
/// ("Unpaid fee paid") have their own words.
String? walletEntryLabel(WalletEntryKind kind) => switch (kind) {
  WalletEntryKind.fee => L10n.current.walletFee,
  WalletEntryKind.debtPaid => L10n.current.walletDebtPaid,
  WalletEntryKind.credit ||
  WalletEntryKind.ride ||
  WalletEntryKind.refund ||
  WalletEntryKind.voucher => null,
};
