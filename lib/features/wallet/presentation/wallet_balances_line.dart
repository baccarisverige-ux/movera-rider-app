import 'package:flutter/material.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// Fix job 6 (owner Q4 2026-11-04, contract v0.18.28 §51): every wallet
/// balance in its own currency, e.g. "65,00 € · 30,00 kr". Never a sum and
/// never converted. Shows nothing while loading, on an error or when the
/// rider holds no balance (the main balance line already shows 0).
class WalletBalancesLine extends StatefulWidget {
  const WalletBalancesLine({super.key, required this.load, this.style});

  /// Reads the balances (`WalletController.loadBalances`).
  final Future<List<Money>> Function() load;
  final TextStyle? style;

  /// "65,00 € · 30,00 kr".
  static String text(List<Money> balances) =>
      balances.map(formatMoney).join(' · ');

  @override
  State<WalletBalancesLine> createState() => _WalletBalancesLineState();
}

class _WalletBalancesLineState extends State<WalletBalancesLine> {
  late Future<List<Money>> _balances = widget.load();

  @override
  void didUpdateWidget(WalletBalancesLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load) _balances = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Money>>(
    future: _balances,
    builder: (context, snapshot) {
      final balances = snapshot.data;
      if (snapshot.hasError || balances == null || balances.length < 2) {
        // One balance (or none) is already the screen's main balance line.
        return const SizedBox.shrink();
      }
      return Text(
        WalletBalancesLine.text(balances),
        key: const ValueKey('wallet-balances-by-currency'),
        style: widget.style,
      );
    },
  );
}
