import 'package:flutter/material.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/plan_return_ride.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/l10n/l10n.dart';

class RideScheduledPage extends StatefulWidget {
  const RideScheduledPage({
    super.key,
    required this.reservationId,
    this.controller,
  });

  final String reservationId;
  final ReservationController? controller;

  static Future<void> open(
    BuildContext context, {
    required String reservationId,
    ReservationController? controller,
    bool replace = false,
    bool untilHome = false,
  }) {
    final route = BottomToTopTransition(
      RideScheduledPage(reservationId: reservationId, controller: controller),
      settings: const RouteSettings(name: AppRoutes.reservationScheduled),
    );
    if (untilHome) {
      return Navigator.pushAndRemoveUntil(context, route, AppRoutes.isHomeRoute);
    }
    if (replace) {
      return Navigator.pushReplacement(context, route);
    }
    return Navigator.push(context, route);
  }

  @override
  State<RideScheduledPage> createState() => _RideScheduledPageState();
}

class _RideScheduledPageState extends State<RideScheduledPage> {
  late final ReservationController _reservations;

  @override
  void initState() {
    super.initState();
    _reservations = widget.controller ?? AppScope.instance.reservations;
    _reservations.addListener(_refresh);
  }

  @override
  void dispose() {
    _reservations.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _goBack() {
    Navigator.maybePop(context);
  }

  void _closeHome() {
    Navigator.of(context).popUntil(AppRoutes.isHomeRoute);
  }

  Future<void> _editReservation(Reservation ride) async {
    if (!ride.status.canEdit) return;
    await Navigator.push(
      context,
      BottomToTopTransition(ScheduleRide(editing: ride)),
    );
  }

  Future<void> _planReturn(Reservation ride) async {
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
  }

  @override
  Widget build(BuildContext context) {
    final ride = _reservations.byId(widget.reservationId);
    final top = MediaQuery.paddingOf(context).top;
    if (ride == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(context.l10n.resNotFound, style: reservationText(16)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          SizedBox(height: top + 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: kReservationSoft,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _goBack,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(
                      Icons.close_rounded,
                      color: kReservationInk,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              children: [
                const ReservationHeroArt(
                  asset: AppAssets.scheduleRideCar,
                  height: 132,
                ),
                const SizedBox(height: 18),
                Text(
                  context.l10n.resScheduledTitle,
                  textAlign: TextAlign.center,
                  style: reservationText(
                    26,
                    weight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ReservationFormat.notifyWhenAssigned,
                  textAlign: TextAlign.center,
                  style: reservationText(
                    14,
                    color: kReservationMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Center(child: ReservationDriverBadge(ride: ride)),
                const SizedBox(height: 22),
                Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: const BorderSide(color: kReservationLine),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      children: [
                        Text(
                          ride.categoryName,
                          style: reservationText(18, weight: FontWeight.w700),
                        ),
                        Text(
                          ReservationFormat.price(ride),
                          style: reservationText(
                            15,
                            weight: FontWeight.w600,
                            color: kReservationMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ReservationFact(
                          asset: AppAssets.scheduleCalendar,
                          label: context.l10n.pickup,
                          value:
                              '${ReservationFormat.longDate(ride.scheduledPickupAt)}  ·  ${ReservationFormat.time(ride.scheduledPickupAt)}',
                        ),
                        ReservationFact(
                          asset: AppAssets.gps,
                          label: context.l10n.resFrom,
                          value: ReservationFormat.shortPlace(
                            ride.pickup.label,
                          ),
                        ),
                        ReservationFact(
                          asset: AppAssets.location,
                          label: context.l10n.resTo,
                          value: ReservationFormat.shortPlace(
                            ride.destination.label,
                          ),
                        ),
                        ReservationFact(
                          asset: AppAssets.payment,
                          label: context.l10n.navPayment,
                          value: paymentLabelFor(ride.paymentMethod),
                          trailing: ReservationPaymentMark(
                            method: ride.paymentMethod,
                          ),
                        ),
                        if (ride.hasPreferences)
                          ReservationFact(
                            asset: AppAssets.note,
                            label: context.l10n.resPreferences,
                            value: RideNotes.displayNote(ride.note!.trim()),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _ReturnRow(onTap: () => _planReturn(ride)),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  ReservationFillButton(
                    label: context.l10n.done,
                    onTap: _closeHome,
                  ),
                  if (ride.status.canEdit) ...[
                    const SizedBox(height: 10),
                    ReservationGhostButton(
                      label: context.l10n.resEdit,
                      onTap: () => _editReservation(ride),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturnRow extends StatelessWidget {
  const _ReturnRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: kReservationLine),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Image.asset(
                AppAssets.calender,
                width: 52,
                height: 52,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.resPlanReturn,
                      style: reservationText(15, weight: FontWeight.w700),
                    ),
                    Text(
                      context.l10n.resPlanReturnBody,
                      style: reservationText(12.5, color: kReservationMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kReservationMuted),
            ],
          ),
        ),
      ),
    );
  }
}
