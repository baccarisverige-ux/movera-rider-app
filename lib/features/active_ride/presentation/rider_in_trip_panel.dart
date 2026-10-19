import 'package:flutter/material.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';

class RiderInTripPanel extends StatelessWidget {
  const RiderInTripPanel({
    super.key,
    required this.destinationAddress,
    required this.rideType,
    required this.paymentMethod,
    this.walletAmountMinor = 0,
    required this.price,
    required this.driver,
    required this.rideId,
    this.status = RideStatus.tripInProgress,
    this.headline,
    required this.onOpenProfile,
    required this.onCall,
    required this.onMore,
    required this.onCancel,
  });

  final String destinationAddress;
  final String rideType;
  final String paymentMethod;

  /// The part of [price] booked to the Movera Wallet, in öre.
  final int walletAmountMinor;
  final double price;
  final MatchedDriver? driver;
  final String? rideId;
  final RideStatus status;

  /// The live arrival time ("Arrive by 08:19") when known; otherwise the
  /// stage name is shown.
  final String? headline;
  final VoidCallback onOpenProfile;
  final VoidCallback onCall;
  final VoidCallback onMore;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final approaching = status == RideStatus.approachingDropoff;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.navigation_rounded,
                            size: 14,
                            color: MoveraTokens.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            approaching ? 'NEAR DESTINATION' : 'ON TRIP',
                            style: waitingText(
                              11,
                              weight: FontWeight.w700,
                              color: MoveraTokens.accent,
                            ).copyWith(letterSpacing: 0.7),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      headline ??
                          (approaching
                              ? 'Approaching destination'
                              : 'Ride in progress'),
                      style: waitingText(23, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      shortPickupPlace(destinationAddress),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: waitingText(
                        14,
                        weight: FontWeight.w500,
                        color: MoveraTokens.muted,
                      ).copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              WaitingShareButton(rideId: rideId),
            ],
          ),
          const SizedBox(height: 12),
          // One slim line: the destination is already the subtitle above.
          Text(
            '$rideType · ${bookedPaymentLine(
              paymentMethod: paymentMethod,
              priceKr: price,
              walletMinor: walletAmountMinor,
            )}',
            key: const ValueKey<String>('trip-summary-line'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: waitingText(
              13.5,
              weight: FontWeight.w500,
              color: MoveraTokens.muted,
            ),
          ),
          const SizedBox(height: 14),
          WaitingDriverCard(
            driver: driver,
            rideId: rideId,
            onOpenProfile: onOpenProfile,
            onCall: onCall,
            onMore: onMore,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFB),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: MoveraTokens.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: MoveraTokens.ink,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Trip safety',
                      style: waitingText(14, weight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SafetyKitSheetRow(rideId: rideId),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey<String>('active-trip-cancel'),
              onPressed: onCancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              // UI-01: on board the trip ends early (paid by distance).
              label: const Text('End trip here'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB42318),
                side: const BorderSide(color: Color(0xFFE4B8B4)),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
