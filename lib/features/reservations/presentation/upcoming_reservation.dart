import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/safety/presentation/ride_check_trip_entry.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/application/reservation_error_message.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/domain/reservation_status.dart';
import 'package:movera_rider/features/reservations/domain/scheduled_ride_rules.dart';
import 'package:movera_rider/features/reservations/presentation/plan_return_ride.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_edit_sheets.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/features/reservations/presentation/ride_scheduled.dart';
import 'package:movera_rider/features/reservations/presentation/scheduled_ride_terms.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/shared/design_system/movera_toast.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/l10n/l10n.dart';

class UpcomingReservationPage extends StatefulWidget {
  const UpcomingReservationPage({
    super.key,
    required this.reservationId,
    this.controller,
  });

  final String reservationId;
  final ReservationController? controller;

  @override
  State<UpcomingReservationPage> createState() =>
      _UpcomingReservationPageState();
}

class _UpcomingReservationPageState extends State<UpcomingReservationPage> {
  late final ReservationController _reservations;
  bool _handedOff = false;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _reservations = widget.controller ?? AppScope.instance.reservations;
    _reservations.addListener(_refresh);
    moveraNavigationEpoch.addListener(_onNavigationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handoffIfLive());
  }

  @override
  void dispose() {
    _freeEndsTimer?.cancel();
    moveraNavigationEpoch.removeListener(_onNavigationChanged);
    _reservations.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
    _handoffIfLive();
  }

  Timer? _freeEndsTimer;
  DateTime? _freeEndsAt;

  /// rider-u172: rebuilds once free cancellation ends, so 'Things to know'
  /// stops saying 'free until …' while the page stays open. Returns
  /// [terms].
  ReservationCancelTerms _rebuildWhenFreeEnds(ReservationCancelTerms terms) {
    if (!terms.freeForNow || _freeEndsAt == terms.freeUntil) return terms;
    _freeEndsTimer?.cancel();
    _freeEndsAt = terms.freeUntil;
    _freeEndsTimer = Timer(
      terms.freeUntil.difference(terms.at) + const Duration(seconds: 1),
      () {
        _freeEndsAt = null;
        if (mounted) setState(() {});
      },
    );
    return terms;
  }

  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  void _onNavigationChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_routeIsCurrent) return;
      _handoffIfLive();
    });
  }

  void _handoffIfLive() {
    final ride = _reservations.byId(widget.reservationId);
    if (ride == null ||
        !ride.revealsDriver ||
        _handedOff ||
        !mounted ||
        !_routeIsCurrent) {
      return;
    }
    _handedOff = true;
    unawaited(_openLiveRide(ride));
  }

  Future<void> _openLiveRide(Reservation snapshot) async {
    // Same safety net as the Home chrono: re-read, and never (re)open a ride
    // that has completed, been cancelled or no longer reveals its driver.
    final ride = _reservations.byId(snapshot.reservationId);
    if (!mounted ||
        !_routeIsCurrent ||
        ride == null ||
        !ride.status.isUpcoming ||
        !ride.revealsDriver) {
      _handedOff = false;
      return;
    }
    await ReservationLiveRide.open(
      context,
      ride,
      controller: _reservations,
    );
    if (!mounted) return;
    _handedOff = false;
    _handoffIfLive();
  }

  Future<void> _editReservation(Reservation ride) async {
    if (!ride.status.canEdit || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await Navigator.push(
        context,
        BottomToTopTransition(ScheduleRide(editing: ride)),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _cancel(Reservation ride) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      // The rider confirms against these terms, so the fee they saw is the
      // fee recorded, even if the free window closes while the sheet is open.
      final terms = _reservations.cancelTermsFor(ride);
      final outcome = await showCancelReservationFlow(
        context,
        ride,
        terms: terms,
      );
      if (!outcome.cancelled) return;
      // rider-u170: the ride may have moved on while the sheets were open.
      final current = _reservations.byId(ride.reservationId);
      if (current == null || !current.status.canCancel) return;
      await _reservations.cancel(
        ride.reservationId,
        reason: outcome.reasonId,
        fee: terms.fee,
      );
    } catch (error, stack) {
      AppScope.instance.crashes.record(
        error,
        stack,
        operation: 'reservation.cancel',
      );
      if (mounted) {
        MoveraToast.show(
          context,
          reservationErrorMessage(error, ReservationAction.cancel),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _planReturn(Reservation ride) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await Navigator.push(
        context,
        RightToLeftTransition(
          PlanReturnRidePage(
            origin: ride,
            controller: _reservations,
            onScheduled: (context, id) => RideScheduledPage.open(
              context,
              reservationId: id,
              controller: _reservations,
              replace: true,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _reservations.byId(widget.reservationId);
    final policy = _reservations.policy;
    final top = MediaQuery.paddingOf(context).top;
    if (ride == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(context.l10n.resNotFound, style: reservationText(16)),
        ),
      );
    }
    // The driver shows as soon as one accepts, unless admin turned that off.
    final showDriver = _reservations.showsDriverOf(ride);
    final previousDriver = ride.previousDriver;
    final noDriverFound = _reservations.isNoDriverFound(ride);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          SizedBox(height: top + 4),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: kReservationInk,
                ),
                tooltip: context.l10n.back,
              ),
              Expanded(
                child: Text(
                  context.l10n.resScheduleCaps,
                  textAlign: TextAlign.center,
                  style: reservationText(
                    10,
                    weight: FontWeight.w600,
                    color: kReservationMuted,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                // rider-j8-2: History opens past rides here too.
                Text(
                  ride.status.isCancelled
                      ? context.l10n.resCancelledReservation
                      : ride.status.isCompleted
                      ? context.l10n.resCompletedRide
                      : context.l10n.resUpcomingRide,
                  style: reservationText(
                    28,
                    weight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ride.status.isUpcoming
                      ? ReservationFormat.reservedHeadline(ride.pickupWallTime)
                      : ReservationFormat.pastHeadline(ride.pickupWallTime),
                  style: reservationText(
                    13.5,
                    color: kReservationMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                ReservationHeroArt(asset: ride.categoryImage, height: 100),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ride.categoryName,
                            style: reservationText(20, weight: FontWeight.w700),
                          ),
                          Text(
                            context.l10n.resSeatsPayment(
                              ride.passengerCount,
                              paymentLabelFor(ride.paymentMethod),
                            ),
                            style: reservationText(
                              12.5,
                              color: kReservationMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      ReservationFormat.price(ride),
                      style: reservationText(18, weight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // rider-j8-1: what Home says once the pickup passed with no
                // driver, never "Reservation confirmed".
                if (noDriverFound)
                  ReservationStatusBanner(
                    key: const Key('upcoming-no-driver-found'),
                    title: context.l10n.termNoDriverFound,
                    body: context.l10n.chronoNoDriverCancel,
                    positive: false,
                  )
                else
                  ReservationStatusBanner(
                    title: ReservationFormat.statusTitle(ride),
                    body: ReservationFormat.statusBody(
                      ride,
                      assignmentDisclaimer: policy.assignmentDisclaimer,
                      showDriver: showDriver,
                    ),
                    positive: !ride.status.isCancelled,
                  ),
                if (showDriver &&
                    ride.driverChanged &&
                    ride.status.isUpcoming) ...[
                  const SizedBox(height: 10),
                  ReservationStatusBanner(
                    key: const Key('reservation-driver-changed'),
                    title: ReservationFormat.driverChangedTitle,
                    body: ReservationFormat.driverChangedBody(
                      previousDriver!,
                      ride.driver!,
                    ),
                  ),
                ] else if (ride.driver == null &&
                    previousDriver != null &&
                    (ride.status == ReservationStatus.scheduled ||
                        ride.isSearchingDriver)) ...[
                  const SizedBox(height: 10),
                  ReservationStatusBanner(
                    key: const Key('reservation-driver-left'),
                    title: ReservationFormat.driverLeftTitle,
                    body: ReservationFormat.driverLeftBody(
                      previousDriver,
                      showName: _reservations.rules.showDriverOnAccept,
                    ),
                    positive: false,
                  ),
                ],
                if (showDriver) ...[
                  const SizedBox(height: 14),
                  ReservationDriverCard(driver: ride.driver!),
                ] else if (ride.driverAssigned && ride.status.isUpcoming) ...[
                  const SizedBox(height: 14),
                  Text(
                    context.l10n.resDriverOnTheWay,
                    style: reservationText(
                      13,
                      color: kReservationMuted,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                ReservationFact(
                  asset: AppAssets.scheduleCalendar,
                  label: context.l10n.resScheduledFor,
                  value:
                      '${ReservationFormat.longDate(ride.pickupWallTime)}, ${ReservationFormat.time(ride.pickupWallTime)}',
                ),
                ReservationFact(
                  asset: AppAssets.gps,
                  label: context.l10n.resPickupAt,
                  value: ride.pickup.label,
                ),
                ReservationFact(
                  asset: AppAssets.location,
                  label: context.l10n.resDropoffAt,
                  value: ride.destination.label,
                ),
                ReservationFact(
                  asset: AppAssets.payment,
                  label: context.l10n.paymentMethod,
                  value: paymentLabelFor(ride.paymentMethod),
                  trailing: ReservationPaymentMark(method: ride.paymentMethod),
                ),
                if (ride.hasPreferences) ...[
                  const SizedBox(height: 12),
                  ReservationFact(
                    asset: AppAssets.note,
                    label: context.l10n.resPreferences,
                    value: RideNotes.displayNote(ride.note!.trim()),
                  ),
                ],
                if (ride.status.isCancelled &&
                    ride.cancellationFee != null) ...[
                  ReservationFact(
                    key: const Key('reservation-cancellation-fee'),
                    asset: AppAssets.payment,
                    label: context.l10n.resCancellationFee,
                    value: ReservationFormat.money(ride.cancellationFee!),
                  ),
                ],
                // RC5: a Ride check on this trip, with its answers.
                RideCheckTripEntry(rideId: ride.reservationId, topSpacing: 14),
                if (ride.status.canEdit) ...[
                  const SizedBox(height: 22),
                  ReservationEditButton(
                    onTap: _actionBusy ? null : () => _editReservation(ride),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    context.l10n.resNeedAnother,
                    style: reservationText(18, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: kReservationSoft,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: _actionBusy ? null : () => _planReturn(ride),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                        child: Row(
                          children: [
                            Image.asset(
                              AppAssets.calender,
                              width: 44,
                              height: 44,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.resPlanReturn,
                                    style: reservationText(
                                      15,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    context.l10n.resPlanReturnBody,
                                    style: reservationText(
                                      12.5,
                                      color: kReservationMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: kReservationMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    context.l10n.resThingsToKnow,
                    style: reservationText(18, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _KnowCard(
                    waiting: policy.waitingSummary,
                    cancellation: ReservationFormat.cancellationSummary(
                      _rebuildWhenFreeEnds(_reservations.cancelTermsFor(ride)),
                    ),
                    pricing: policy.pricingSummary,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => ScheduledRideTermsPage.open(
                      context,
                      controller: _reservations,
                      reservationId: ride.reservationId,
                    ),
                    child: Text(
                      context.l10n.resViewTerms,
                      style: reservationText(
                        14.5,
                        weight: FontWeight.w600,
                        color: kReservationAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: TextButton(
                      onPressed: _actionBusy ? null : () => _cancel(ride),
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFF4F5F6),
                        foregroundColor: const Color(0xFFB42318),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        context.l10n.cancelReservation,
                        style: reservationText(
                          15,
                          weight: FontWeight.w600,
                          color: const Color(0xFFB42318),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReservationDriverCard extends StatelessWidget {
  const ReservationDriverCard({super.key, required this.driver});

  final ReservationDriver driver;

  @override
  Widget build(BuildContext context) {
    final car = driver.carLabel;
    return Semantics(
      container: true,
      label: [
        context.l10n.resYourDriverName(driver.displayFirstName),
        if (car != null) car,
        // rider-68: in the app language.
        if (driver.plate != null) context.l10n.resPlateLabel(driver.plate!),
      ].join(', '),
      child: Container(
        key: const Key('reservation-driver-card'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          border: Border.all(color: kReservationLine),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.resYourDriverCaps,
              style: reservationText(
                10.5,
                weight: FontWeight.w600,
                color: kReservationMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: kReservationSoft,
                  backgroundImage: driver.photoAsset == null
                      ? null
                      : AssetImage(driver.photoAsset!),
                  child: driver.photoAsset == null
                      ? (driver.initial.isEmpty
                            ? const Icon(
                                Icons.person_outline_rounded,
                                size: 20,
                                color: kReservationMuted,
                              )
                            : Text(
                                driver.initial,
                                style: reservationText(
                                  18,
                                  weight: FontWeight.w700,
                                ),
                              ))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              driver.displayFirstName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: reservationText(
                                16,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (driver.rating != null) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: Color(0xFFE0A100),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              driver.rating!.toStringAsFixed(2),
                              style: reservationText(
                                13.5,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (car != null)
                        Text(
                          car,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: reservationText(
                            13,
                            color: kReservationMuted,
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
                ),
                if (driver.plate != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: kReservationSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kReservationLine),
                    ),
                    child: Text(
                      driver.plate!,
                      style: reservationText(
                        13,
                        weight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KnowCard extends StatelessWidget {
  const _KnowCard({
    required this.waiting,
    required this.cancellation,
    required this.pricing,
  });

  final String waiting;
  final String cancellation;
  final String pricing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kReservationLine),
      ),
      child: Column(
        children: [
          _KnowItem(index: '01', title: context.l10n.resWaitingTime, body: waiting),
          const Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: kReservationLine,
          ),
          _KnowItem(index: '02', title: context.l10n.resCancellation, body: cancellation),
          const Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: kReservationLine,
          ),
          _KnowItem(index: '03', title: context.l10n.resPricing, body: pricing),
        ],
      ),
    );
  }
}

class _KnowItem extends StatelessWidget {
  const _KnowItem({
    required this.index,
    required this.title,
    required this.body,
  });

  final String index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              index,
              style: reservationText(
                12,
                weight: FontWeight.w600,
                color: kReservationAccent,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: reservationText(
                    11,
                    weight: FontWeight.w600,
                    color: kReservationInk,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: reservationText(
                    13,
                    color: kReservationMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
