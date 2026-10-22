import 'package:flutter/material.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_trip_entry.dart';
import 'package:movera_rider/features/history/application/on_demand_history_controller.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/movera_loader.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/design_system/movera_hit_area.dart';
import 'package:movera_rider/features/support/application/support_controller.dart';
import 'package:movera_rider/features/support/presentation/support.dart';
import 'package:movera_rider/l10n/l10n.dart';

class RideHistory extends StatefulWidget {
  const RideHistory({super.key, this.reservations, this.onDemandReader});

  /// Pop result asking the opener to start a booking (D-026). The side menu
  /// answers it by opening Home's destination sheet.
  static const startBookingResult = 'movera.rideHistory.startBooking';

  final ReservationController? reservations;
  final Future<List<Reservation>> Function()? onDemandReader;

  @override
  State<RideHistory> createState() => _RideHistoryState();
}

class _RideHistoryState extends State<RideHistory> {
  static const Color _ink = Color(0xFF1D252C);
  static const Color _muted = Color(0xFF5C656C);
  static const Color _line = Color(0xFFE7EBEE);
  static const Color _accent = Color(0xFF2D5878);
  static const Color _cta = Color(0xFF11181D);
  static const OnDemandHistoryController _onDemandController =
      OnDemandHistoryController();
  late final ReservationController _reservations;
  List<Reservation> _onDemand = const [];
  bool _onDemandLoading = true;
  bool _onDemandFailed = false;

  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _reservations = widget.reservations ?? AppScope.instance.reservations;
    _reservations.addListener(_onReservations);
    _loadOnDemand();
  }

  @override
  void dispose() {
    _reservations.removeListener(_onReservations);
    super.dispose();
  }

  void _onReservations() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOnDemand() async {
    if (!mounted) return;
    if (!_onDemandLoading || _onDemandFailed) {
      setState(() {
        _onDemandLoading = true;
        _onDemandFailed = false;
      });
    }
    try {
      final reader = widget.onDemandReader ?? _onDemandController.load;
      final rides = await reader();
      if (!mounted) return;
      setState(() {
        _onDemand = rides;
        _onDemandLoading = false;
        _onDemandFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _onDemandLoading = false;
        _onDemandFailed = true;
      });
    }
  }

  TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = _ink,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.poppins(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  void _openSchedule() {
    Navigator.push(context, BottomToTopTransition(const ScheduleRide()));
  }

  Future<void> _showHowItWorks() async {
    // NAV-12: the sheet closes with a choice and Schedule opens only after
    // its exit animation has finished (MoveraSheet.show waits for that).
    final schedule = await MoveraSheet.show<bool>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
              const SizedBox(height: 20),
              Text(
                context.l10n.scheduledRides,
                style: _text(20, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.historyHowBody,
                style: _text(14, color: _muted, height: 1.45),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: _cta,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: Text(
                    context.l10n.scheduleARide,
                    style: _text(
                      16,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (schedule == true && mounted) _openSchedule();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: top + 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                  tooltip: context.l10n.back,
                ),
                const Spacer(),
                IconButton(
                  onPressed: _showHowItWorks,
                  icon: const Icon(Icons.info_outline_rounded, color: _ink),
                  tooltip: context.l10n.historyHow,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text(
              context.l10n.rides,
              style: _text(34, weight: FontWeight.w700, letterSpacing: -0.8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _tabLabel(context.l10n.upcoming, 0),
                _tabLabel(context.l10n.resCompleted, 1),
                _tabLabel(context.l10n.resCancelled, 2),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          Expanded(
            child: _tab == 0
                ? _upcoming()
                : _tab == 1
                ? _completedList()
                : _cancelledList(),
          ),
        ],
      ),
    );
  }

  Widget _tabLabel(String label, int index) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = index),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10, top: 6),
              child: Text(
                label,
                style: _text(
                  15,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? _ink : _muted,
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: selected ? 36 : 0,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _upcoming() {
    final upcoming = _reservations.upcoming();
    if (upcoming.isEmpty) return _emptyUpcoming();
    // UI-19: cards are built lazily; the last item is the Schedule button.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      itemCount: upcoming.length + 1,
      itemBuilder: (context, index) {
        if (index < upcoming.length) {
          final ride = upcoming[index];
          return ReservationHistoryCard(
            ride: ride,
            onTap: () {
              Navigator.push(
                context,
                RightToLeftTransition(
                  UpcomingReservationPage(
                    reservationId: ride.reservationId,
                    controller: _reservations,
                  ),
                ),
              );
            },
          );
        }
        return _scheduleButton();
      },
    );
  }

  Widget _scheduleButton() {
    return Column(
      children: [
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton(
            onPressed: _openSchedule,
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: _line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: Text(
              context.l10n.scheduleARide,
              style: _text(16, weight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyUpcoming() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 20),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 140,
                      child: Image.asset(
                        'assets/images/schedule_timeline_exact_v3.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      context.l10n.noUpcomingRides,
                      style: _text(22, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.l10n.noUpcomingBody,
                      textAlign: TextAlign.center,
                      style: _text(14.5, color: _muted, height: 1.45),
                    ),
                    const SizedBox(height: 16),
                    MoveraHitArea(
                      label: context.l10n.learnHow,
                      onTap: _showHowItWorks,
                      child: ExcludeSemantics(
                        child: Text(
                          context.l10n.learnHow,
                          style: _text(
                            15,
                            weight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: _openSchedule,
              style: FilledButton.styleFrom(
                backgroundColor: _cta,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: Text(
                context.l10n.scheduleARide,
                style: _text(
                  16.5,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _completedList() =>
      _combinedHistory(_reservations.completed(), completed: true);

  Widget _cancelledList() =>
      _combinedHistory(_reservations.cancelled(), completed: false);

  Widget _combinedHistory(
    List<Reservation> reservations, {
    required bool completed,
  }) {
    final rides = _onDemandController.combine(
      reservations,
      _onDemand,
      completed: completed,
    );
    return _reservationHistory(rides, completed: completed);
  }

  Widget _reservationHistory(
    List<Reservation> reservations, {
    required bool completed,
  }) {
    if (_onDemandLoading && reservations.isEmpty) {
      return Center(
        child: MoveraLoader(
          title: context.l10n.loadingRides,
          message: context.l10n.checkingHistory,
        ),
      );
    }
    if (_onDemandFailed && reservations.isEmpty) {
      return Center(
        child: MoveraEmptyState(
          icon: Icons.error_outline_rounded,
          title: context.l10n.historyLoadFailed,
          message: context.l10n.historyLoadFailedBody,
          actionLabel: context.l10n.retry,
          onAction: _loadOnDemand,
        ),
      );
    }
    if (reservations.isEmpty) {
      return Center(
        child: MoveraEmptyState(
          icon: completed ? Icons.route_outlined : Icons.event_busy_outlined,
          title: completed ? context.l10n.noCompletedRides : context.l10n.noCancelledRides,
          message: completed
              ? context.l10n.noCompletedBody
              : context.l10n.noCancelledBody,
          actionLabel: context.l10n.bookARide,
          onAction: () =>
              Navigator.maybePop(context, RideHistory.startBookingResult),
        ),
      );
    }
    // UI-19: cards are built lazily.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      itemCount: reservations.length,
      itemBuilder: (context, index) {
        final ride = reservations[index];
        return ReservationHistoryCard(
          ride: ride,
          onTap: () => _openHistoryRide(ride),
        );
      },
    );
  }

  void _openHistoryRide(Reservation ride) {
    if (!ride.reservationId.startsWith('ondemand-')) {
      Navigator.push(
        context,
        RightToLeftTransition(
          UpcomingReservationPage(
            reservationId: ride.reservationId,
            controller: _reservations,
          ),
          settings: const RouteSettings(name: AppRoutes.reservationUpcoming),
        ),
      );
      return;
    }
    MoveraSheet.show<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
            const SizedBox(height: 18),
            Text(
              ride.status.isCompleted
                  ? context.l10n.completedRide
                  : ride.endedEarly
                  ? context.l10n.endedEarly
                  : context.l10n.cancelledRide,
              style: _text(21, weight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            ReservationRoutePreview(
              pickup: ride.pickup.label,
              destination: ride.destination.label,
              height: 132,
            ),
            const SizedBox(height: 14),
            Text(
              ride.chargedFare != null
                  ? context.l10n.historyCharged(
                      ride.categoryName,
                      ReservationFormat.price(ride),
                    )
                  : context.l10n.historyBooked(
                      ride.categoryName,
                      ReservationFormat.price(ride),
                    ),
              key: const ValueKey('history-detail-price'),
              style: _text(15, weight: FontWeight.w700),
            ),
            if (ride.endedEarly) ...[
              const SizedBox(height: 5),
              Text(
                context.l10n.historyEndedEarly,
                style: _text(13.5, color: _muted),
              ),
            ],
            if (ride.cancellationFee case final fee? when fee.isPositive) ...[
              const SizedBox(height: 5),
              Text(
                context.l10n.cancelFee(ReservationFormat.money(fee)),
                style: _text(13.5, color: _muted),
              ),
            ],
            const SizedBox(height: 5),
            Text(
              ReservationFormat.historyWhen(ride),
              style: _text(13.5, color: _muted),
            ),
            const SizedBox(height: 5),
            Text(
              context.l10n.paymentMethodLine(
                // rider-38: Wallet and Card in the app language too.
                L10n.isCashLabel(ride.paymentMethod)
                    ? context.l10n.payCash
                    : paymentLabelFor(ride.paymentMethod),
              ),
              style: _text(13.5, color: _muted),
            ),
            if (ride.cancellationReason?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 5),
              Text(
                context.l10n.reasonLine(ReservationFormat.reasonLabel(ride.cancellationReason!)),
                style: _text(13.5, color: _muted),
              ),
            ],
            // RC5: a Ride check on this trip, with its answers.
            RideCheckTripEntry(
              rideId: ride.reservationId.substring('ondemand-'.length),
              topSpacing: 14,
            ),
            const SizedBox(height: 6),
            // UI-07: the completion screen is not the only way to report a
            // problem with a ride.
            TextButton.icon(
              key: const ValueKey('history-get-help'),
              onPressed: () {
                Navigator.pop(context);
                guardedPush(
                  this.context,
                  RightToLeftTransition(
                    SelectIssue(ride: SupportController.rideFor(ride)),
                  ),
                );
              },
              icon: const Icon(Icons.help_outline_rounded),
              label: Text(context.l10n.getHelpWithRide),
            ),
          ],
        ),
      ),
    );
  }
}
