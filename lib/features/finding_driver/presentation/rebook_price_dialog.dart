import 'package:flutter/material.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// A booking asked again is priced again: a price other than the one the
/// rider last saw (a surge, their own raise) is booked only once they accept
/// it (rider-u107). Used after "No driver found" and by "Search again".
Future<bool> showRebookPriceDialog(
  BuildContext context, {
  required Money shown,
  required Money next,
}) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('rebook-price-updated'),
      title: Text(context.l10n.priceUpdated),
      content: Text(
        context.l10n.priceUpdatedBody(formatMoney(next), formatMoney(shown)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.l10n.notNow),
        ),
        FilledButton(
          key: const ValueKey('rebook-price-accept'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(context.l10n.bookForPrice(formatMoney(next))),
        ),
      ],
    ),
  );
  return accepted == true;
}
