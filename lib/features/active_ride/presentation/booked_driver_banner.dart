import 'package:flutter/material.dart';
import 'package:movera_rider/features/ride_booking/application/rider_trip_watch.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// v0.18.32 owner Q1 "Live ride + banner" (contract.json#bookedRideSeen
/// .liveWins): the live ride stays on screen and a small banner says the
/// booked ride's driver is already heading to the rider.
class BookedDriverBanner extends StatelessWidget {
  const BookedDriverBanner({super.key, this.watch});

  /// Tests pass their own; the app uses [RiderTripWatch.instance].
  final RiderTripWatch? watch;

  @override
  Widget build(BuildContext context) {
    final notifier = (watch ?? RiderTripWatch.instance).bookedDriverOnTheWay;
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, onTheWay, _) {
        if (!onTheWay) return const SizedBox.shrink();
        final top = MediaQuery.of(context).padding.top + 10;
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, top, 16, 0),
            child: Semantics(
              liveRegion: true,
              child: Material(
                key: const ValueKey('booked-driver-banner'),
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event_available_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          L10n.current.bookedDriverOnTheWay,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
