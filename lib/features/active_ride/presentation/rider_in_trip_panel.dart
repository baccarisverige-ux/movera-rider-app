import 'package:movera_rider/features/finding_driver/presentation/games/search_games.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:flutter/material.dart';
import 'package:movera_rider/features/active_ride/presentation/ride_slot_animations.dart';
import 'package:movera_rider/core/config/driver_profile_settings.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_on_way_card.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_selection/presentation/ride_labels.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/features/active_ride/presentation/waiting_sheet_bits.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/l10n/l10n.dart';

class RiderInTripPanel extends StatelessWidget {
  const RiderInTripPanel({
    super.key,
    required this.destinationAddress,
    required this.rideType,
    required this.paymentMethod,
    this.walletAmountMinor = 0,
    required this.price,
    this.currency = Money.defaultCurrency,
    required this.driver,
    required this.rideId,
    this.status = RideStatus.tripInProgress,
    this.headline,
    required this.onOpenProfile,
    required this.onCall,
    this.onMore,
    required this.onCancel,
    this.stopNote,
    this.stopPaused = false,
  });

  final String destinationAddress;
  final String rideType;
  final String paymentMethod;

  /// The part of [price] booked to the Movera Wallet, in öre.
  final int walletAmountMinor;
  final double price;

  /// ISO-4217 code of [price] (the trip's zone).
  final String currency;
  final MatchedDriver? driver;
  final String? rideId;
  final RideStatus status;

  /// The live arrival time ("Arrive by 08:19") when known; otherwise the
  /// stage name is shown.
  final String? headline;
  final VoidCallback onOpenProfile;
  final VoidCallback onCall;

  /// Null where the route cannot change (rider-u55).
  final VoidCallback? onMore;
  final VoidCallback onCancel;

  /// v0.18.9 (G7 decision 4): the price of waiting at a stop, when the trip
  /// has stops ("Waiting at a stop: 4,50 kr/min").
  final String? stopNote;

  /// v0.18.108 (`contract.json#autoArrive.stops`, job C9b; owner
  /// decisions/driver-g7.md:84 "At the pickup AND at stops"): the server
  /// stopped the wait at the open stop (`stops[i].away`, the driver is away
  /// from it). Says so (texts.riderStopPaused); no amounts.
  final bool stopPaused;

  @override
  Widget build(BuildContext context) {
    final approaching = status == RideStatus.approachingDropoff;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Owner 2026-11-23 (on-trip-animation.html): the approved
          // animation at the top of the panel.
          const Center(child: OnTripAnimation()),
          const SizedBox(height: 8),
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
                          // rider-u39: the label ellipsizes rather than
                          // overflow the pill (Swedish, large text).
                          Flexible(
                            child: Text(
                              approaching
                                  ? context.l10n.nearDestinationUpper
                                  : context.l10n.onTripUpper,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: waitingText(
                                11,
                                weight: FontWeight.w700,
                                color: MoveraTokens.accent,
                              ).copyWith(letterSpacing: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      headline ??
                          (approaching
                              ? context.l10n.approachingDestination
                              : context.l10n.etaRideInProgress),
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
                    if (stopNote case final note?) ...[
                      const SizedBox(height: 4),
                      Text(
                        note,
                        key: const ValueKey('in-trip-stop-price'),
                        style: waitingText(13, color: MoveraTokens.muted),
                      ),
                    ],
                    if (stopPaused) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.stopWaitingPausedDriverAway,
                        key: const ValueKey('in-trip-stop-paused'),
                        style: waitingText(
                          13,
                          weight: FontWeight.w600,
                          color: MoveraTokens.ink,
                        ),
                      ),
                    ],
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
            '${rideNameFor(rideType)} · ${bookedPaymentLine(
              // rider-u231: the method in the app language.
              paymentMethod: paymentLabelFor(paymentMethod),
              priceKr: price,
              currency: currency,
              walletMinor: walletAmountMinor,
            )}',
            key: const ValueKey<String>('trip-summary-line'),
            // B8 (finder 2026-11-07): the line wraps; on one line the wallet
            // part and the amount were cut off at 320 px in French.
            style: waitingText(
              13.5,
              weight: FontWeight.w500,
              color: MoveraTokens.muted,
            ),
          ),
          const SizedBox(height: 14),
          // Owner 2026-11-23: the same driver card as before pickup during
          // the trip (contract.json#driverProfile; the profile read works
          // until 24 h after the end). Zone switch off: the old block.
          if (DriverProfileSettings.current.on)
            DriverOnWayCard(
              driver: driver,
              rideId: rideId,
              onOpenProfile: onOpenProfile,
              onCall: onCall,
              onMore: onMore,
            )
          else
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
                    Flexible(
                      child: Text(
                        context.l10n.tripSafety,
                        style: waitingText(14, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SafetyKitSheetRow(rideId: rideId),
              ],
            ),
          ),
          // Owner 2026-11-23 (screen 3): "Avsluta resan här" lives in the
          // ⋯ menu as its last red row; without that menu it stays here.
          // Without a driver card (no driver data) the ⋯ is not shown,
          // so the end button stays reachable here.
          if (onMore == null || driver == null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('active-trip-cancel'),
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 18),
                // UI-01: on board the trip ends early (paid by distance).
                label: Text(context.l10n.endTripHere),
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
          // Owner 2026-11-23: the games row at the bottom of the sheet.
          const SizedBox(height: 16),
          const SearchGamesRow(),
        ],
      ),
    );
  }
}
