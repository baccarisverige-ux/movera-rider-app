import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/widgets/price_updated_dialog.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_labels.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// A booking asked again is priced again: a price HIGHER than the one the
/// rider last saw (a surge, their own raise) is booked only once they accept
/// it (rider-u107; v0.18.174: callers ask only when [priceChangeNeedsAsk], a
/// drop books silently). Used after "No driver found" and by "Search again".
/// Since v0.18.174 it opens the shared v8 [PriceUpdatedDialog]; [shown] is
/// kept for the callers (the popup shows only the new price).
Future<bool> showRebookPriceDialog(
  BuildContext context, {
  required Money shown,
  required Money next,
  required String categoryName,
}) {
  return PriceUpdatedDialog.show(
    context,
    categoryName: categoryName,
    price: formatMoney(next),
    keyPrefix: 'rebook',
  );
}

/// The ride name the rebook popup's button shows: the screen's own ride
/// label ([rideType], as the screen shows it), else the catalog's name for
/// [categoryId] (the resolver di.dart uses), else the id.
String rebookCategoryName(String rideType, String? categoryId) {
  if (rideType.trim().isNotEmpty) return rideNameFor(rideType);
  if (categoryId == null) return '';
  String? label;
  try {
    label = AppScope.instance.catalog.labelOf(categoryId);
  } catch (_) {
    label = null;
  }
  return rideNameFor(label ?? categoryId);
}
