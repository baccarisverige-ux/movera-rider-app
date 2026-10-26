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
import 'package:movera_rider/features/home/presentation/widgets/home_sheet_layout.dart';
import 'package:movera_rider/shared/widgets/custom_text_widget.dart';
import 'package:movera_rider/shared/widgets/responsive_size.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/l10n/l10n.dart';

const _ink = Color(0xFF1D252C);
// UI-6: was 0xFF6B757D (4.27:1 on the card fill).
const _muted = MoveraTokens.subtleOnFill;
// UI-6: was 0xFF8A939B (3.12:1 on white).
const _label = MoveraTokens.subtle;
const _card = Color(0xFFF3F4F5);
const _line = Color(0xFFE7EBEE);
const _teal = Color(0xFF2A7A84);
const _art = 'assets/images/menu';

/// The height of a "Start your journey" card, in design px.
const double journeyCardHeightDesign = 104;

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

  /// The month's name in the app language ("October", "octobre").
  String get monthName => L10n.formatDate(month, 'MMMM');

  static int weeksIn(DateTime month) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    return ((days - 1) ~/ 7) + 1;
  }

  static MonthRideStats fromRides(Iterable<Reservation> rides, DateTime now) {
    final weeks = List<int>.filled(weeksIn(now), 0);
    var count = 0;
    var electric = 0;
    final totals = <String, Money>{};
    void add(Money price) {
      final total = totals[price.currency];
      totals[price.currency] = total == null ? price : total + price;
    }

    for (final ride in rides) {
      final at = ride.pickupWallTime;
      if (at.year != now.year || at.month != now.month) continue;
      if (!ride.status.isCompleted) {
        // rider-r5-15: not a completed ride, but an ended-early trip's
        // charge or a cancel fee is money the rider paid this month.
        final paid = ride.chargedFare ?? ride.cancellationFee;
        if (paid != null && paid.isPositive) add(paid);
        continue;
      }
      count++;
      if (ride.categoryId == 'electric') electric++;
      weeks[(at.day - 1) ~/ 7]++;
      // A trip whose payment failed was taken but not paid: it is a ride,
      // not money spent.
      if (ride.paymentFailed) continue;
      add(Money.fromLegacyMajor(ride.price, ride.currency));
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
    return [
      L10n.current.homeRideCount(rides),
      for (final total in spent) formatMoney(total, whole: true),
    ].join(' · ');
  }
}

/// "Your month" stats card + "Start your journey" strip shown under "Plan
/// ahead" on Home's expanded sheet. Owner round 1: the Help centre row is
/// gone from here; Help stays in Account and the side menu.
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

class _HomeJourneySectionState extends State<HomeJourneySection>
    with WidgetsBindingObserver {
  late MonthRideStats _stats;
  StreamSubscription<void>? _changes;
  Listenable? _reservations;

  /// rider-r5-24: whether a history read has succeeded. Until one has,
  /// the card states no count (a failed read is not "0 rides"), and the
  /// read is tried again when the app comes back to the foreground.
  bool _known = false;

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
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    _reservations?.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_known) _load();
  }

  /// rider-u126: bumped by every [_load]; only the newest read is shown.
  int _loadGeneration = 0;

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final rides =
          await (widget.ridesLoader ?? HomeJourneySection.defaultRides)();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _stats = MonthRideStats.fromRides(rides, _now);
        _known = true;
      });
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
        _MonthCard(stats: _stats, known: _known),
        SizedBox(height: HomeSheetLayout.sectionGap),
        Padding(
          padding: EdgeInsets.only(left: ResSize.w * 2, bottom: ResSize.h * 7),
          child: TextWidget(
            text: context.l10n.homeStartYourJourney,
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
                title: context.l10n.homeCatchFlight,
                picture: 'at_the_airport',
                onTap: widget.onOpenSchedule,
              ),
            ),
            SizedBox(width: ResSize.w * 8),
            Expanded(
              child: _JourneyCard(
                title: context.l10n.homeComfortCar,
                picture: 'by_the_road',
                onTap: _rideType('comfort'),
              ),
            ),
            SizedBox(width: ResSize.w * 8),
            Expanded(
              child: _JourneyCard(
                title: context.l10n.homeTopChauffeur,
                picture: 'well_done',
                onTap: _rideType('premium'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.stats, this.known = true});

  final MonthRideStats stats;
  final bool known;

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
        borderRadius: BorderRadius.circular(HomeSheetLayout.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextWidget(
                  text: context.l10n.homeYourMonth(stats.monthName),
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
                  text: known ? stats.pillText : '–',
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
                          text: context.l10n.homeRidesPerWeek,
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
                                text: context.l10n.homeCo2Kg(
                                  L10n.formatDecimal(stats.co2AvoidedKg),
                                ),
                                color: _ink,
                                fontSize: 14,
                                fontWeight: fwBold,
                              ),
                              TextWidget(
                                text: context.l10n.homeCo2Avoided,
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
        borderRadius: BorderRadius.circular(HomeSheetLayout.cardRadius),
        child: Container(
          // Owner round 1: taller (was 88) now that Help centre is gone,
          // so the expanded sheet fills.
          height: ResSize.h * journeyCardHeightDesign,
          padding: EdgeInsets.fromLTRB(
            ResSize.w * 9,
            ResSize.h * 8,
            ResSize.w * 9,
            ResSize.h * 7,
          ),
          decoration: BoxDecoration(
            color: AppColor.white,
            borderRadius: BorderRadius.circular(HomeSheetLayout.cardRadius),
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
