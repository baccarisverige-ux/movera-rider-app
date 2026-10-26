import 'package:movera_rider/core/contracts/money.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_notes.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/presentation/ride_safety_kit.dart';
import 'package:movera_rider/features/safety/presentation/trip_share_page.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/messages/presentation/chat.dart';
import 'package:movera_rider/shared/accessibility/a11y.dart';
import 'package:movera_rider/shared/design_system/movera_empty_state.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';
import 'package:movera_rider/features/wallet/domain/wallet_split.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:movera_rider/features/payments/presentation/payment_labels.dart';
import 'package:movera_rider/l10n/l10n.dart';

String shortPickupPlace(String raw) {
  final value = L10n.place(raw);
  final noisy = RegExp(
    r'^(sweden|sverige|stockholms?\s*län|stockholm\s*county|'
    r'kommun|municipality|county|län|europe)$',
    caseSensitive: false,
  );
  final parts = value
      .split(RegExp(r'[,|]'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .where((part) => !RegExp(r'^\d{3,}(\s?\d{2})?$').hasMatch(part))
      .where((part) => !noisy.hasMatch(part))
      .toList();
  if (parts.isEmpty) {
    final fallback = value.trim();
    return fallback.length <= 42 ? fallback : '${fallback.substring(0, 40)}…';
  }
  if (parts.length == 1) {
    final only = parts.first;
    return only.length <= 42 ? only : '${only.substring(0, 40)}…';
  }
  final short = '${parts[0]}, ${parts[1]}';
  return short.length <= 48 ? short : '${short.substring(0, 46)}…';
}

TextStyle waitingText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
}) {
  return GoogleFonts.poppins(
    fontSize: size,
    fontWeight: weight,
    color: color ?? MoveraTokens.ink,
  );
}

class WaitingShareButton extends StatelessWidget {
  const WaitingShareButton({super.key, this.rideId});

  final String? rideId;

  void _share(BuildContext context) {
    final safety = SafetyController.shared;
    if (safety.preferences.tripShareEnabled) {
      showRideSafetyKit(context, rideId: rideId);
      return;
    }
    Navigator.push(
      context,
      RightToLeftTransition(TripSharePage(controller: safety)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.shareTrip,
      child: Material(
        color: const Color(0xFFF6F8FA),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _share(context),
          // rider-u64: the 44 px floor; the 20 px icon was a 40 px target.
          child: const SizedBox.square(
            dimension: A11y.minTapIOS,
            child: Icon(
              Icons.ios_share_rounded,
              size: 20,
              color: MoveraTokens.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class WaitingRideDetailsCard extends StatelessWidget {
  const WaitingRideDetailsCard({
    super.key,
    required this.rideType,
    required this.pickupAddress,
    this.destinationAddress,
    this.inTrip = false,
    required this.paymentMethod,
    this.walletAmountMinor = 0,
    required this.price,
    this.currency = Money.defaultCurrency,
    this.onMore,
  });

  final String rideType;
  final String pickupAddress;
  final String? destinationAddress;
  final bool inTrip;
  final String paymentMethod;

  /// The part of [price] booked to the Movera Wallet, in öre.
  final int walletAmountMinor;
  final double price;

  /// ISO-4217 code of [price] (the trip's zone).
  final String currency;

  /// Null where the route cannot change (rider-u55): no ⋯ button.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: MoveraTokens.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rideType,
                  style: waitingText(
                    12,
                    weight: FontWeight.w500,
                    color: const Color(0xFF5C656C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  inTrip && destinationAddress?.trim().isNotEmpty == true
                      ? context.l10n.toPlace(
                          shortPickupPlace(destinationAddress!),
                        )
                      : context.l10n.meetAt(shortPickupPlace(pickupAddress)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: waitingText(
                    15,
                    weight: FontWeight.w600,
                  ).copyWith(height: 1.3),
                ),
                const SizedBox(height: 8),
                Text(
                  bookedPaymentLine(
                    // rider-u231: the method in the app language.
                    paymentMethod: paymentLabelFor(paymentMethod),
                    priceKr: price,
                    currency: currency,
                    walletMinor: walletAmountMinor,
                  ),
                  style: waitingText(
                    12,
                    weight: FontWeight.w500,
                    color: MoveraTokens.accent,
                  ),
                ),
              ],
            ),
          ),
          if (onMore != null)
            IconButton(
              onPressed: onMore,
              icon: const Icon(Icons.more_horiz_rounded),
              tooltip: context.l10n.rideDetails,
            ),
        ],
      ),
    );
  }
}

class WaitingDriverCard extends StatefulWidget {
  const WaitingDriverCard({
    super.key,
    required this.driver,
    this.rideId,
    required this.onOpenProfile,
    required this.onCall,
    this.onMore,
  });

  final MatchedDriver? driver;
  final String? rideId;
  final VoidCallback onOpenProfile;
  final VoidCallback onCall;

  /// Null where the route cannot change (rider-u55): no ⋯ button.
  final VoidCallback? onMore;

  @override
  State<WaitingDriverCard> createState() => _WaitingDriverCardState();
}

class _WaitingDriverCardState extends State<WaitingDriverCard> {
  bool _openingChat = false;

  /// The ride's conversation, for the unread badge. It follows what the
  /// trip screen polls on the live wire (and what the demo ingests), so a
  /// message that arrives while this card is up shows at once.
  late MessagesController _messages = MessagesController.forRide(widget.rideId);

  @override
  void initState() {
    super.initState();
    _messages.addListener(_onMessagesChanged);
  }

  @override
  void didUpdateWidget(WaitingDriverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rideId == widget.rideId) return;
    _messages.dispose();
    _messages = MessagesController.forRide(widget.rideId)
      ..addListener(_onMessagesChanged);
  }

  @override
  void dispose() {
    _messages.dispose();
    super.dispose();
  }

  void _onMessagesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openChat(String? rideId, String driverName) async {
    if (_openingChat) return;
    _openingChat = true;
    try {
      await Navigator.push(
        context,
        BottomToTopTransition(Chat(driverName: driverName, rideId: rideId)),
      );
    } finally {
      _openingChat = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.driver;
    final rideId = widget.rideId;
    final onOpenProfile = widget.onOpenProfile;
    final onCall = widget.onCall;
    final onMore = widget.onMore;
    if (driver == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: MoveraTokens.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: MoveraEmptyState(
          icon: Icons.person_search_outlined,
          title: context.l10n.driverDetailsUnavailable,
          message: context.l10n.driverDetailsUnavailableBody,
          compact: true,
        ),
      );
    }
    final d = driver;
    final unreadMessages = _messages.unreadCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        border: Border.all(color: MoveraTokens.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onOpenProfile,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundImage: d.photoAsset != null
                          ? AssetImage(d.photoAsset!)
                          : null,
                      backgroundColor: const Color(0xFFF3F6FB),
                      child: d.photoAsset == null
                          ? (d.initial.isEmpty
                                ? const Icon(
                                    Icons.person_outline_rounded,
                                    size: 22,
                                    color: Color(0xFF6E7881),
                                  )
                                : Text(
                                    d.initial,
                                    style: waitingText(
                                      18,
                                      weight: FontWeight.w700,
                                    ),
                                  ))
                          : null,
                    ),
                    if (d.ratingLabel != null)
                      Positioned(
                        left: 2,
                        right: 2,
                        bottom: -9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: MoveraTokens.ink,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '★ ${d.ratingLabel}',
                            textAlign: TextAlign.center,
                            style: waitingText(
                              10,
                              weight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.displayFirstName,
                        style: waitingText(18, weight: FontWeight.w700),
                      ),
                      if (d.tripsLabel != null)
                        Text(
                          context.l10n.driverTripCount(d.tripCount!),
                          style: waitingText(
                            12,
                            color: const Color(0xFF5C656C),
                          ),
                        ),
                      if (d.vehicleLabel.isNotEmpty)
                        Text(
                          d.vehicleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: waitingText(
                            13,
                            weight: FontWeight.w500,
                            color: const Color(0xFF5C656C),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (d.vehicleImageAsset != null)
                      Image.asset(
                        excludeFromSemantics: true,
                        d.vehicleImageAsset!,
                        height: 40,
                        width: 72,
                        fit: BoxFit.contain,
                      ),
                    if (d.plate != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F8FA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: MoveraTokens.line),
                        ),
                        child: Text(
                          d.plate!,
                          style: waitingText(
                            14,
                            weight: FontWeight.w700,
                          ).copyWith(letterSpacing: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: const Color(0xFFF6F8FA),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => _openChat(rideId, d.displayFirstName),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: MoveraTokens.ink,
                          ),
                          const SizedBox(width: 8),
                          // rider-u65: ellipsize rather than run under the
                          // call chip (Swedish, large text, unread badge).
                          Flexible(
                            child: Text(
                              context.l10n.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: waitingText(14, weight: FontWeight.w600),
                            ),
                          ),
                          if (unreadMessages > 0) ...[
                            const SizedBox(width: 7),
                            Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: MoveraTokens.accent,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                unreadMessages > 99 ? '99+' : '$unreadMessages',
                                textAlign: TextAlign.center,
                                style: waitingText(
                                  10,
                                  weight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _IconChip(
                icon: Icons.phone_outlined,
                onTap: onCall,
                semanticLabel: context.l10n.callDriver,
              ),
              if (onMore != null) ...[
                const SizedBox(width: 8),
                _IconChip(
                  icon: Icons.more_horiz_rounded,
                  onTap: onMore,
                  semanticLabel: context.l10n.moreOptions,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class WaitingNotesAndPin extends StatelessWidget {
  const WaitingNotesAndPin({super.key, required this.notes, this.rideId});

  final RideNotes notes;

  /// rider-u66: the screen's ride (a reservation's id on a scheduled live
  /// ride), which SOS, trip sharing and recording target. Null: the
  /// on-demand session's ride.
  final String? rideId;

  @override
  Widget build(BuildContext context) {
    final safety = SafetyController.shared;
    // The notes chips depend only on `notes` (this widget's own field), not
    // on SafetyController at all - building them once here, instead of
    // inside ListenableBuilder's builder, avoids rebuilding them on every
    // unrelated safety/PIN notification.
    final notesContent = notes.isEmpty
        ? const SizedBox.shrink()
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in notes.selected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F6FB),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        RideNotes.labelFor(label),
                        style: waitingText(
                          12,
                          weight: FontWeight.w600,
                          color: MoveraTokens.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
    return ListenableBuilder(
      listenable: safety,
      child: notesContent,
      builder: (context, child) => _buildContent(context, safety, child!),
    );
  }

  Widget _buildContent(
    BuildContext context,
    SafetyController safety,
    Widget notesContent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        notesContent,
        if (safety.loading || !safety.hasLoaded) ...[
          const SizedBox(height: 12),
          Text(
            context.l10n.loadingPin,
            style: waitingText(12, color: const Color(0xFF5C656C)),
          ),
        ] else if (safety.preferences.pinRequired) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F8FA),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  safety.pin.isAvailable
                      ? context.l10n.showPinToDriver
                      : context.l10n.pinUnavailable,
                  style: waitingText(12, color: const Color(0xFF5C656C)),
                ),
                if (safety.pin.isAvailable)
                  Text(
                    safety.pin.pin,
                    style: waitingText(22, weight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        SafetyKitSheetRow(rideId: rideId ?? AppScope.instance.ride.rideId),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, size: 20, color: MoveraTokens.ink),
          ),
        ),
      ),
    );
  }
}
