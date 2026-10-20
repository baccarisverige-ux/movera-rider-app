import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/shared/formatters/money.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appcolors.dart';
import 'package:movera_rider/core/constants/appfontweight.dart';
import 'package:movera_rider/features/history/application/on_demand_history_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';

const _ink = Color(0xFF1D252C);
// UI-6: was 0xFF6B757D (4.27:1 on the card fill).
const _muted = MoveraTokens.subtleOnFill;
// UI-6: was 0xFF8A939B (3.12:1 on white).
const _label = MoveraTokens.subtle;
const _card = Color(0xFFF3F4F5);
const _line = Color(0xFFE7EBEE);
const _teal = Color(0xFF2A7A84);
const _art = 'assets/images/menu';

/// Rides this device completed in one calendar month, grouped for the
/// "Your month" card. The backend will later own these figures.
class MonthRideStats {
  const MonthRideStats({
    required this.month,
    required this.rides,
    required this.spent,
    required this.ridesPerWeek,
    this.electricRides = 0,
  });

  final DateTime month;
  final int rides;

  /// Q11: what the month cost, one total per currency (never converted),
  /// in the card's order: SEK, EUR, TND, then any other code.
  final List<Money> spent;
  final List<int> ridesPerWeek;

  /// Completed Electric rides this month: the only ones that avoid
  /// tailpipe CO₂ (FLOW-13; petrol rides used to count too).
  final int electricRides;

  /// Rough tailpipe estimate avoided versus a solo petrol trip, per Electric
  /// ride. Shown as an estimate; replaced by server figures once the backend
  /// reports distance and vehicle class per ride.
  static const double co2PerRideKg = 0.4;

  double get co2AvoidedKg => electricRides * co2PerRideKg;

  static const _names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String get monthName => _names[month.month - 1];

  static int weeksIn(DateTime month) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    return ((days - 1) ~/ 7) + 1;
  }

  static MonthRideStats fromRides(Iterable<Reservation> rides, DateTime now) {
    final weeks = List<int>.filled(weeksIn(now), 0);
    var count = 0;
    var electric = 0;
    final totals = <String, Money>{};
    for (final ride in rides) {
      if (!ride.status.isCompleted) continue;
      final at = ride.scheduledPickupAt;
      if (at.year != now.year || at.month != now.month) continue;
      count++;
      if (ride.categoryId == 'electric') electric++;
      final price = Money.fromLegacyMajor(ride.price, ride.currency);
      final total = totals[price.currency];
      totals[price.currency] = total == null ? price : total + price;
      weeks[(at.day - 1) ~/ 7]++;
    }
    return MonthRideStats(
      month: DateTime(now.year, now.month),
      rides: count,
      spent: totals.values.toList()..sort(_byCurrency),
      ridesPerWeek: weeks,
      electricRides: electric,
    );
  }

  static const _currencyOrder = ['SEK', 'EUR', 'TND'];

  static int _byCurrency(Money a, Money b) {
    int rank(String code) {
      final i = _currencyOrder.indexOf(code);
      return i < 0 ? _currencyOrder.length : i;
    }

    final byRank = rank(a.currency).compareTo(rank(b.currency));
    return byRank != 0 ? byRank : a.currency.compareTo(b.currency);
  }

  /// "3 rides · 820 kr · 24,00 €": the ride count, then each currency's
  /// total in the app's one money format.
  String get pillText {
    final rideWord = rides == 1 ? 'ride' : 'rides';
    return [
      '$rides $rideWord',
      for (final total in spent) formatMoney(total, whole: true),
    ].join(' · ');
  }
}

/// "Your month" stats card + "Start your journey" strip + Help centre row
/// shown under "Plan ahead" on Home's expanded sheet.
class HomeJourneySection extends StatefulWidget {
  const HomeJourneySection({
    super.key,
    required this.onDestinationTap,
    required this.onOpenSchedule,
    this.onRideTypeTap,
    this.ridesLoader,
    this.clock,
    this.changes,
  });

  final VoidCallback onDestinationTap;
  final VoidCallback onOpenSchedule;

  /// Books with a ride category already chosen (NAV-11): "Comfort car" opens
  /// Comfort, "Highly rated chauffeur" Premium (top-rated drivers). Without
  /// it the cards fall back to [onDestinationTap].
  final void Function(String rideId)? onRideTypeTap;
  final Future<List<Reservation>> Function()? ridesLoader;
  final DateTime Function()? clock;

  /// When to re-read the month (FLOW-13); defaults to ride history and
  /// reservation changes.
  final Stream<void>? changes;

  static Future<List<Reservation>> defaultRides() async {
    final onDemand = await OnDemandHistoryController().load();
    final scheduled = AppScope.instance.reservations.all;
    return [...onDemand, ...scheduled];
  }

  @override
  State<HomeJourneySection> createState() => _HomeJourneySectionState();
}

class _HomeJourneySectionState extends State<HomeJourneySection> {
  late MonthRideStats _stats;
  StreamSubscription<void>? _changes;
  Listenable? _reservations;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _stats = MonthRideStats.fromRides(const [], _now);
    // FLOW-13: Home stays mounted under the ride flow, so a ride finished
    // since the first read must refresh the card, not wait for a rebuild.
    final changes = widget.changes;
    if (changes != null) {
      _changes = changes.listen((_) => _load());
    } else {
      _changes = const OnDemandHistoryController().changes.listen(
        (_) => _load(),
      );
      _reservations = AppScope.instance.reservations..addListener(_load);
    }
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    _reservations?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rides =
          await (widget.ridesLoader ?? HomeJourneySection.defaultRides)();
      if (!mounted) return;
      setState(() => _stats = MonthRideStats.fromRides(rides, _now));
    } catch (_) {
      // Keep the empty month; the card is informational only.
    }
  }

  VoidCallback _rideType(String rideId) {
    final open = widget.onRideTypeTap;
    if (open == null) return widget.onDestinationTap;
    return () => open(rideId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MonthCard(stats: _stats),
        SizedBox(height: ResSize.h * 10),
        Padding(
          padding: EdgeInsets.only(left: ResSize.w * 2, bottom: ResSize.h * 7),
          child: TextWidget(
            text: 'START YOUR JOURNEY',
            color: _label,
            fontSize: 10.5,
            fontWeight: fwSemiBold,
            letterSpacing: 0.4,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _JourneyCard(
                title: 'Catch your flight',
                picture: 'at_the_airport',
                onTap: widget.onOpenSchedule,
              ),
            ),
            SizedBox(width: ResSize.w * 8),
            Expanded(
              child: _JourneyCard(
                title: 'Comfort car',
                picture: 'by_the_road',
                onTap: _rideType('comfort'),
              ),
            ),
            SizedBox(width: ResSize.w * 8),
            Expanded(
              child: _JourneyCard(
                title: 'Highly rated chauffeur',
                picture: 'well_done',
                onTap: _rideType('premium'),
              ),
            ),
          ],
        ),
        SizedBox(height: ResSize.h * 8),
        _HelpRow(
          onTap: () => Navigator.push(
            context,
            RightToLeftTransition(const SupportHome()),
          ),
        ),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.stats});

  final MonthRideStats stats;

  @override
  Widget build(BuildContext context) {
    // UI-2: the tiles keep their drawn height at normal text and grow by the
    // extra line height large text needs (Poppins lines are about 1.5x).
    final labelSize = ResSize.setSp(10);
    final labelGrowth =
        (MediaQuery.textScalerOf(context).scale(labelSize) - labelSize) * 1.5;
    final tileHeight = ResSize.h * 58 + math.max(0.0, labelGrowth);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        ResSize.w * 12,
        ResSize.h * 10,
        ResSize.w * 12,
        ResSize.h * 10,
      ),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextWidget(
                  text: 'Your ${stats.monthName}',
                  color: _ink,
                  fontSize: 13.5,
                  fontWeight: fwSemiBold,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResSize.w * 8,
                  vertical: ResSize.h * 3,
                ),
                decoration: BoxDecoration(
                  color: AppColor.white,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: TextWidget(
                  text: stats.pillText,
                  color: _muted,
                  fontSize: 10,
                  fontWeight: fwMedium,
                ),
              ),
            ],
          ),
          SizedBox(height: ResSize.h * 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 15,
                child: _Tile(
                  height: tileHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: TextWidget(
                          text: 'Rides per week',
                          color: _muted,
                          fontSize: 10,
                          fontWeight: fwNormal,
                        ),
                      ),
                      SizedBox(height: ResSize.h * 4),
                      Expanded(child: _WeekBars(counts: stats.ridesPerWeek)),
                    ],
                  ),
                ),
              ),
              SizedBox(width: ResSize.w * 8),
              Expanded(
                flex: 11,
                child: _Tile(
                  height: tileHeight,
                  child: Row(
                    children: [
                      SizedBox(
                        width: ResSize.w * 30,
                        height: ResSize.h * 30,
                        child: SvgPicture.asset(
                          '$_art/nature.svg',
                          fit: BoxFit.contain,
                        ),
                      ),
                      SizedBox(width: ResSize.w * 6),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextWidget(
                                text:
                                    '${stats.co2AvoidedKg.toStringAsFixed(1)} kg',
                                color: _ink,
                                fontSize: 14,
                                fontWeight: fwBold,
                              ),
                              TextWidget(
                                text: 'est. CO₂ avoided',
                                color: _muted,
                                fontSize: 9,
                                fontWeight: fwNormal,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: ResSize.w * 10,
        vertical: ResSize.h * 8,
      ),
      decoration: BoxDecoration(
        color: AppColor.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.counts});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final max = counts.fold<int>(0, (m, c) => c > m ? c : m);
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxHeight;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < counts.length; i++) ...[
              if (i > 0) SizedBox(width: ResSize.w * 4),
              Expanded(
                child: Container(
                  height: max == 0
                      ? full * 0.18
                      : (full * (0.18 + 0.82 * counts[i] / max)),
                  decoration: BoxDecoration(
                    color: max == 0 || counts[i] == 0
                        ? _line
                        : _teal.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.title,
    required this.picture,
    required this.onTap,
  });

  final String title;
  final String picture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: ResSize.h * 88,
          padding: EdgeInsets.fromLTRB(
            ResSize.w * 9,
            ResSize.h * 8,
            ResSize.w * 9,
            ResSize.h * 7,
          ),
          decoration: BoxDecoration(
            color: AppColor.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: ResSize.h * 33,
                child: TextWidget(
                  text: title,
                  color: _ink,
                  fontSize: 10.5,
                  fontWeight: fwSemiBold,
                ),
              ),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: SvgPicture.asset(
                    '$_art/$picture.svg',
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          // UI-2: grows with large text instead of clipping it.
          constraints: BoxConstraints(minHeight: ResSize.h * 52),
          padding: EdgeInsets.symmetric(horizontal: ResSize.w * 12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              SizedBox(
                width: ResSize.w * 54,
                height: ResSize.h * 42,
                child: SvgPicture.asset('$_art/faq.svg', fit: BoxFit.contain),
              ),
              SizedBox(width: ResSize.w * 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextWidget(
                      text: 'Help centre',
                      color: _ink,
                      fontSize: 12.5,
                      fontWeight: fwSemiBold,
                    ),
                    TextWidget(
                      text: 'Answers to common questions, any time',
                      color: _muted,
                      fontSize: 10,
                      fontWeight: fwNormal,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFB8C0C7)),
            ],
          ),
        ),
      ),
    );
  }
}
