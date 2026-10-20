enum WalletEntryKind { credit, ride, refund, voucher }

class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.kind,
    required this.amountMinor,
    required this.at,
    this.currency = 'SEK',
    this.note,
  });

  /// ISO-4217 code of [amountMinor] (Q8: one balance per currency).
  final String currency;

  final String id;
  final WalletEntryKind kind;
  final int amountMinor;
  final DateTime at;
  final String? note;
}

class WalletLedger {
  final List<WalletEntry> _entries = [];

  List<WalletEntry> get entries => List.unmodifiable(_entries);

  /// The kronor balance (the home currency's movements only).
  int get balanceMinor => balanceMinorIn('SEK');

  /// The sum of the movements in [currency] (never mixed across
  /// currencies, Q8).
  int balanceMinorIn(String currency) => _entries
      .where((e) => e.currency == currency)
      .fold(0, (sum, e) => sum + e.amountMinor);

  void add(WalletEntry entry) => _entries.add(entry);

  /// Empties the ledger at the end of a rider's session.
  void clear() => _entries.clear();
}
