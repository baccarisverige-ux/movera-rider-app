import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// v0.18.174 (contract.json#priceChangeAsk; owner 2026-11-28 "When price more
/// allways show", "No popup, book lower"): the price at booking is asked
/// again only when it ROSE, by any amount (even 1 cent / 1 öre). A drop or
/// the same price books silently at the fresh (server) price. No tolerance.
/// Compared on minor units; another currency always asks.
bool priceChangeNeedsAsk(Money agreed, Money fresh) =>
    fresh.currency != agreed.currency || fresh.amountMinor > agreed.amountMinor;

/// v0.18.174: the server's `409 price_changed_ask` (the booked quote is
/// higher than the agreed one and the rider has not accepted it).
bool isPriceChangedAsk(Object error) =>
    error is ApiError && error.reason == 'price_changed_ask';

/// The server's fresh price from a `price_changed_ask` answer (its details
/// line `fresh:<minor> <currency>`), or null when it is not there.
Money? priceChangedAskFresh(Object error) {
  if (!isPriceChangedAsk(error)) return null;
  for (final line in (error as ApiError).details ?? const <String>[]) {
    final match = RegExp(r'^fresh:(\d+) ([A-Z]{3})$').firstMatch(line);
    if (match != null) {
      return Money(int.parse(match.group(1)!), match.group(2)!);
    }
  }
  return null;
}

/// The one "price recalculated" popup of the rider app (owner FINAL design
/// v8, 2026-11-28; Rules plan/screens-2026-11-28/price-updated/
/// new-design-mockup-v8-bw.png). Black and white only: white card, a small
/// ↻ left of the bold title, one grey line, the price ONLY in the black
/// button "Réserver {category} · {price}", a ✕ at the top right. No old
/// price, no "Pas maintenant" button: the ✕ (and a barrier tap or system
/// back) returns false, exactly what "Pas maintenant" did; the button
/// returns true, exactly what "Réserver" did.
///
/// Used by all 6 proven cases through two thin wrappers (Rule 21: both kept):
/// Choose your ride `_acceptNewPrice` (select_ride_quotes.dart) and
/// `showRebookPriceDialog` (rebook_price_dialog.dart).
class PriceUpdatedDialog extends StatelessWidget {
  const PriceUpdatedDialog({
    super.key,
    required this.categoryName,
    required this.price,
    required this.keyPrefix,
  });

  /// The selected ride's name as the rider reads it (`rideNameFor`).
  final String categoryName;

  /// The new price, already formatted with its exact cents / öre.
  final String price;

  /// `select-ride` or `rebook`: keeps the existing test keys
  /// (`<prefix>-price-updated`, `-price-accept`) and adds `-price-close`.
  final String keyPrefix;

  static const ink = Color(0xFF000000);
  static const card = Color(0xFFFFFFFF);
  static const grey = Color(0xFF6E6E6E);

  /// Opens the popup on the root navigator. True: the rider books at
  /// [price]; false: closed (nothing booked).
  static Future<bool> show(
    BuildContext context, {
    required String categoryName,
    required String price,
    required String keyPrefix,
  }) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x80000000),
      builder: (_) => PriceUpdatedDialog(
        categoryName: categoryName,
        price: price,
        keyPrefix: keyPrefix,
      ),
    );
    return accepted == true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    TextStyle text(double size, FontWeight weight, Color color) =>
        GoogleFonts.poppins(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.35,
        );
    return Dialog(
      key: ValueKey('$keyPrefix-price-updated'),
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(20),
          // A soft shadow (owner v8), no Material tint.
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 40,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.refresh_rounded, size: 20, color: ink),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            l10n.priceRecalculatedTitle,
                            style: text(19, FontWeight.w600, ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.priceUpdatedRecalculated,
                    style: text(14.5, FontWeight.w400, grey),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: TextButton(
                      key: ValueKey('$keyPrefix-price-accept'),
                      style: TextButton.styleFrom(
                        backgroundColor: ink,
                        foregroundColor: card,
                        overlayColor: card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        l10n.bookCategoryForPrice(categoryName, price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text(15.5, FontWeight.w500, card),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Semantics(
                button: true,
                label: l10n.priceUpdatedClose,
                excludeSemantics: true,
                child: IconButton(
                  key: ValueKey('$keyPrefix-price-close'),
                  tooltip: l10n.priceUpdatedClose,
                  icon: const Icon(Icons.close_rounded, size: 22, color: ink),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
