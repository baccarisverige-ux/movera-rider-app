import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/promotions/application/rider_promotion_controller.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';

/// A ride's price before and after the promotion, in kr.
typedef PromotionPrice = ({double original, double discounted});

/// One ride category as the details sheet lists it.
class PromotionCategory {
  const PromotionCategory({required this.id, required this.name});

  final String id;
  final String name;
}

/// Rides left, validity, per-category prices and rules of the promotion.
///
/// Opened from the promo ticket on the categories screen with the current
/// quotes, so every category shows its price with the promotion; opened
/// elsewhere (Pay with) without prices it only says which categories are
/// included.
class PromotionDetailsSheet extends StatelessWidget {
  const PromotionDetailsSheet({
    super.key,
    required this.promotion,
    required this.categories,
    this.prices = const {},
    this.now,
    this.currency = Money.defaultCurrency,
    this.cap,
  });

  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _line = Color(0xFFE7EBEE);
  static const Color _accent = Color(0xFF2D5878);
  static const Color _accentSoft = Color(0xFFEAF2F8);
  static const Color _cta = Color(0xFF11181D);
  static const Color _warn = Color(0xFFB4452B);

  final RiderPromotion promotion;
  final List<PromotionCategory> categories;

  /// Current quote prices by category id; empty when no destination is set.
  final Map<String, PromotionPrice> prices;

  /// ISO-4217 code of [prices] (the pickup's zone).
  final String currency;

  /// Q10: the most a promotion takes off one trip in this zone, set by
  /// Admin per country (`RiderAppConfig.promoCap`), in [currency]. Null:
  /// no cap is set, and none is shown.
  final Money? cap;

  /// Clock for the "days left" line; tests pin it.
  final DateTime? now;

  /// Opens the sheet. [categories] default to the ride catalog; [prices] are
  /// the current quotes when the caller has them.
  static Future<void> open(
    BuildContext context,
    RiderPromotion promotion, {
    List<PromotionCategory>? categories,
    Map<String, PromotionPrice> prices = const {},
    String? currency,
  }) async {
    final list =
        categories ??
        [
          for (final ride in AppScope.instance.rideCatalog.rides())
            PromotionCategory(id: ride.id, name: ride.name),
        ];
    // Without a trip, the zone the rider is in decides the money.
    final code = currency ?? (await currentRiderZone()).currency;
    Money? cap;
    try {
      cap = (await AppScope.instance.riderConfig.forTrip(currency: code))
          ?.promoCap;
    } catch (_) {
      cap = null;
    }
    if (!context.mounted) return;
    return MoveraSheet.show<void>(
      context: context,
      builder: (_) => PromotionDetailsSheet(
        promotion: promotion,
        categories: list,
        prices: prices,
        currency: code,
        cap: cap,
      ),
    );
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _date(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// "Valid until 30 Nov 2026 · 48 days left", "Ends today" or "Expired".
  static String validityText(RiderPromotion promotion, DateTime now) {
    final ends = promotion.endsAt?.toLocal();
    if (ends == null) return 'No end date';
    if (!now.isBefore(ends)) return 'Expired ${_date(ends)}';
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(ends.year, ends.month, ends.day);
    final days = last.difference(today).inDays;
    if (days <= 0) return 'Ends today';
    return 'Valid until ${_date(ends)} · $days ${days == 1 ? 'day' : 'days'} left';
  }

  String _kr(double major) =>
      formatMoney(Money.fromLegacyMajor(major, currency), whole: true);

  TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color c = _ink}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: w, color: c);

  @override
  Widget build(BuildContext context) {
    final clock = now ?? DateTime.now();
    final ends = promotion.endsAt;
    final expired = ends != null && !clock.isBefore(ends);
    final usedUp = promotion.ridesLeft <= 0;
    final over = expired || usedUp;
    final left = promotion.ridesLeft.clamp(0, promotion.ridesTotal);
    final used = (promotion.ridesTotal - left).clamp(0, 999);
    final inset = MediaQuery.paddingOf(context).bottom;
    final max = cap != null && cap!.currency == currency ? cap : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _line,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Image.asset(
                AppAssets.promoCard,
                height: 70,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(height: 10),
            Text(promotion.title, style: _t(20, w: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${promotion.percentOff}% off · $left of '
                    '${promotion.ridesTotal} rides left',
                    style: _t(13, c: _muted),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: over ? const Color(0xFFF6F5F1) : _accentSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    expired
                        ? 'Expired'
                        : usedUp
                        ? 'All used'
                        : '$left left',
                    style: _t(
                      12,
                      w: FontWeight.w600,
                      c: over ? _muted : _accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: promotion.ridesTotal == 0
                    ? 0
                    : used / promotion.ridesTotal,
                minHeight: 6,
                backgroundColor: _accentSoft,
                color: _accent,
              ),
            ),
            const SizedBox(height: 14),
            _meta(
              Icons.schedule_rounded,
              validityText(promotion, clock),
              color: expired ? _warn : _muted,
            ),
            if (max != null) ...[
              const SizedBox(height: 6),
              _meta(
                Icons.sell_outlined,
                'Max ${formatMoneyShort(max)} off per ride',
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Your prices with this promotion',
              style: _t(15, w: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final category in categories) _categoryRow(category),
            if (prices.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Prices show once you choose a destination.',
                style: _t(12.5, c: _muted),
              ),
            ],
            if (promotion.rules.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final rule in promotion.rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $rule', style: _t(12.5, c: _muted)),
                ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                key: const ValueKey('promotion-details-close'),
                style: FilledButton.styleFrom(
                  backgroundColor: _cta,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Got it',
                  style: _t(15, w: FontWeight.w600, c: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color color = _muted}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: _t(13, c: color)),
        ),
      ],
    );
  }

  Widget _categoryRow(PromotionCategory category) {
    final included = promotion.appliesTo(category.id);
    final price = prices[category.id];
    final Widget trailing;
    if (price == null) {
      trailing = Text(
        included ? 'Included' : 'Not included',
        style: _t(
          13,
          w: included ? FontWeight.w600 : FontWeight.w500,
          c: included ? _accent : _muted,
        ),
      );
    } else if (!included || price.discounted >= price.original) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_kr(price.original), style: _t(14, w: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('Not included', style: _t(12, c: _muted)),
        ],
      );
    } else {
      trailing = Semantics(
        label:
            'Was ${_kr(price.original)}, now ${_kr(price.discounted)} '
            'with the promotion',
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _kr(price.original),
                style: _t(
                  13,
                  c: _muted,
                ).copyWith(decoration: TextDecoration.lineThrough),
              ),
              const SizedBox(width: 8),
              Text(_kr(price.discounted), style: _t(15, w: FontWeight.w700)),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              category.name,
              style: _t(14, c: included ? _ink : _muted),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
