import 'dart:async';

import 'package:flutter/material.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_widgets.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';

Future<void> showReservationBookedPopup(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: context.l10n.resRideScheduled,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondary) {
      return const ReservationBookedPopup();
    },
    transitionBuilder: (context, animation, secondary, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      );
    },
  );
}

class ReservationBookedPopup extends StatefulWidget {
  const ReservationBookedPopup({super.key});

  @override
  State<ReservationBookedPopup> createState() => _ReservationBookedPopupState();
}

class _ReservationBookedPopupState extends State<ReservationBookedPopup> {
  // A Future.delayed cannot be called off, so the auto-dismiss kept running
  // after the popup was gone. A Timer can be cancelled in dispose.
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _autoDismiss = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PointerInterceptor(
      child: Center(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: 300,
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(AppAssets.sucess, height: 92, fit: BoxFit.contain),
                const SizedBox(height: 16),
                Text(
                  context.l10n.resBooked,
                  textAlign: TextAlign.center,
                  style: reservationText(22, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.resBookedBody,
                  textAlign: TextAlign.center,
                  style: reservationText(
                    14,
                    color: kReservationMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
