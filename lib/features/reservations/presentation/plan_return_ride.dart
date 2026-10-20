import 'package:flutter/material.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/ride_selection/presentation/select_ride.dart';
import 'package:movera_rider/features/scheduled_rides/presentation/schedule_ride.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Return-ride booking reuses the shared category selector.
/// A new reservation is created only after the rider confirms.
class PlanReturnRidePage extends StatelessWidget {
  const PlanReturnRidePage({
    super.key,
    required this.origin,
    this.controller,
    this.onScheduled,
  });

  final Reservation origin;
  final ReservationController? controller;
  final Future<void> Function(BuildContext context, String reservationId)?
  onScheduled;

  @override
  Widget build(BuildContext context) {
    // CODE-5: without the exact points of the first ride the return would be
    // booked at invented coordinates; send the rider to plan it instead.
    if (!SelectRide.canPlanReturn(origin)) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.resPlanYourReturn)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.resReturnNoPlaces),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(builder: (_) => const ScheduleRide()),
                ),
                child: Text(context.l10n.resScheduleARide),
              ),
            ],
          ),
        ),
      );
    }
    return SelectRide.forReturnRide(
      origin,
      reservations: controller,
      onScheduled: onScheduled,
    );
  }
}
