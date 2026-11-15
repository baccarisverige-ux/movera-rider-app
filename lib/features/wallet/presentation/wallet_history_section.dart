import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/features/wallet/domain/wallet_history.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// The wallet history on the Wallet page (BQ-V41 = BQ-V20, owner G12 Q5
/// decisions/driver-g12.md:12 "rider app wallet history shows 'Credit from
/// Movera'"). Every line is the server's entry: its kind's label, its date
/// and its amount exactly as sent, in its currency's decimals (owner rule
/// R2: nothing is worked out on the phone). "Show more" reads the next page
/// with the server's cursor.
class WalletHistorySection extends StatefulWidget {
  const WalletHistorySection({super.key, required this.source});

  final WalletHistorySource source;

  @override
  State<WalletHistorySection> createState() => _WalletHistorySectionState();
}

class _WalletHistorySectionState extends State<WalletHistorySection> {
  static const _ink = Color(0xFF11181D);
  static const _muted = Color(0xFF5C656C);
  static const _line = Color(0xFFE6E8E7);

  final List<WalletHistoryEntry> _items = [];
  String? _next;
  bool _loading = true;
  bool _failed = false;
  bool _moreBusy = false;
  bool _moreFailed = false;

  @override
  void initState() {
    super.initState();
    _first();
  }

  @override
  void didUpdateWidget(WalletHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) _first();
  }

  Future<void> _first() async {
    setState(() {
      _loading = true;
      _failed = false;
      _moreFailed = false;
    });
    final source = widget.source;
    try {
      final page = await source.load();
      if (!mounted || !identical(source, widget.source)) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _next = page.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || !identical(source, widget.source)) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _more() async {
    final cursor = _next;
    if (cursor == null || _moreBusy) return;
    setState(() {
      _moreBusy = true;
      _moreFailed = false;
    });
    final source = widget.source;
    try {
      final page = await source.load(cursor: cursor);
      if (!mounted || !identical(source, widget.source)) return;
      setState(() {
        _items.addAll(page.items);
        _next = page.nextCursor;
        _moreBusy = false;
      });
    } catch (_) {
      if (!mounted || !identical(source, widget.source)) return;
      setState(() {
        _moreBusy = false;
        _moreFailed = true;
      });
    }
  }

  TextStyle _style(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = _ink,
  }) => GoogleFonts.poppins(fontSize: size, fontWeight: weight, color: color);

  /// The server's amount as sent: "+125,50 kr" in, "-12.345 DT" out.
  static String _amount(Money amount) {
    final shown = formatMoneyFull(amount);
    return amount.amountMinor > 0 ? '+$shown' : shown;
  }

  /// "14 Nov 2026, 11:00" in the app's language.
  static String _when(DateTime at) =>
      '${L10n.formatDate(at, 'yMMMd')}, ${L10n.formatTime(at)}';

  Widget _row(WalletHistoryEntry entry) {
    final l10n = context.l10n;
    return Padding(
      key: ValueKey('wallet-history-${entry.id}'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  walletEntryLabel(entry.kind, l10n),
                  style: _style(14, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _when(entry.at.toLocal()),
                  style: _style(12, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _amount(entry.amount),
            style: _style(
              14,
              weight: FontWeight.w700,
              color: entry.amount.amountMinor > 0
                  ? const Color(0xFF1B7F4B)
                  : _ink,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_failed) {
      body = MoveraEmptyState(
        icon: Icons.error_outline_rounded,
        title: l10n.walletHistoryLoadFailed,
        message: l10n.walletHistoryLoadFailedBody,
        actionLabel: l10n.retry,
        onAction: _first,
        compact: true,
      );
    } else if (_items.isEmpty) {
      body = MoveraEmptyState(
        key: const ValueKey('wallet-history-empty'),
        icon: Icons.receipt_long_outlined,
        title: l10n.walletHistoryEmpty,
        message: l10n.walletHistoryEmptyBody,
        compact: true,
      );
    } else {
      body = Column(
        children: [
          for (final (i, entry) in _items.indexed) ...[
            if (i > 0) const Divider(height: 1, color: _line),
            _row(entry),
          ],
          if (_moreFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.walletHistoryLoadFailed,
                style: _style(12, color: _muted),
              ),
            ),
          if (_next != null)
            TextButton(
              key: const ValueKey('wallet-history-more'),
              onPressed: _moreBusy ? null : _more,
              child: _moreBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_moreFailed ? l10n.retry : l10n.walletHistoryMore),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.walletHistoryTitle,
          style: _style(15, weight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        body,
      ],
    );
  }
}
