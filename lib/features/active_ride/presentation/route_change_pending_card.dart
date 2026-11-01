import 'package:flutter/material.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/on_trip.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// Contract v0.18.9 (owner G7 decision 3): the rider confirmed a new route;
/// the driver answers Accept or Refuse. Until then the trip goes on to the
/// first destination, and the rider may take the change back.
class RouteChangePendingCard extends StatelessWidget {
  const RouteChangePendingCard({
    super.key,
    required this.change,
    required this.onWithdraw,
    this.withdrawing = false,
  });

  final TripRouteChange change;
  final VoidCallback onWithdraw;
  final bool withdrawing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = change.total;
    final difference = change.difference;
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('route-change-pending'),
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.g7RouteWaiting,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (total != null)
                    Text(
                      l10n.g7RouteNewPrice(
                        formatMoney(total),
                        difference == null ? '' : signedDifference(difference),
                      ),
                      key: const ValueKey('route-change-pending-price'),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            TextButton(
              key: const ValueKey('route-change-withdraw'),
              onPressed: withdrawing ? null : onWithdraw,
              child: Text(l10n.g7RouteWithdraw),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+60 kr" / "−15 kr": the price difference with its sign.
String signedDifference(Money difference) {
  final shown = formatMoney(
    Money(difference.amountMinor.abs(), difference.currency),
  );
  return difference.amountMinor < 0 ? '−$shown' : '+$shown';
}
