import 'package:flutter/material.dart';
import 'package:movera_rider/app/deferred_screens.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_photo_avatar.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_profile_sheet.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

/// v0.18.147 "driver on the way" card (owner 2026-11-20 "Now build all";
/// our own design in Movera colours): photo with a rating badge, first
/// name with the verified tick, trips and since-year, a Swedish-style plate
/// with the car model and colour, a large filled Call and a soft Message
/// with an unread dot. A tap on the card opens the driver profile sheet
/// (one read, cached; no polling); when the zone turns the profile off or
/// the read fails, [onOpenProfile] opens the simple page as before.
///
/// Same parameters as WaitingDriverCard, so the waiting sheet swaps one
/// line (a separate hook change, after rider #676).
class DriverOnWayCard extends StatefulWidget {
  const DriverOnWayCard({
    super.key,
    required this.driver,
    this.rideId,
    required this.onOpenProfile,
    required this.onCall,
    this.onMore,
    this.verified = true,
    this.now,
  });

  final MatchedDriver? driver;
  final String? rideId;
  final VoidCallback onOpenProfile;
  final VoidCallback onCall;
  final VoidCallback? onMore;

  /// A matched driver is an approved one; the profile read says it exactly.
  final bool verified;
  final DateTime? now;

  @override
  State<DriverOnWayCard> createState() => _DriverOnWayCardState();
}

class _DriverOnWayCardState extends State<DriverOnWayCard> {
  late MessagesController _messages = MessagesController.forRide(widget.rideId);
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _messages.addListener(_changed);
  }

  @override
  void didUpdateWidget(DriverOnWayCard old) {
    super.didUpdateWidget(old);
    if (old.rideId == widget.rideId) return;
    _messages.dispose();
    _messages = MessagesController.forRide(widget.rideId)
      ..addListener(_changed);
  }

  @override
  void dispose() {
    _messages.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _openProfile() async {
    if (_opening) return;
    _opening = true;
    try {
      final rideId = widget.rideId;
      final driver = widget.driver;
      final shown =
          rideId != null &&
          driver != null &&
          await showDriverProfileSheet(context, tripId: rideId, driver: driver);
      if (!shown && mounted) widget.onOpenProfile();
    } finally {
      _opening = false;
    }
  }

  Future<void> _openChat(String name) async {
    await Navigator.push(
      context,
      BottomToTopTransition(
        chatScreen(driverName: name, rideId: widget.rideId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = widget.driver;
    if (d == null) return const SizedBox.shrink();
    final years = d.yearsOnMovera;
    final sinceYear = years == null
        ? null
        : (widget.now ?? DateTime.now()).year - years;
    final unread = _messages.unreadCount;
    final car = [
      d.vehicleMake,
      d.vehicleModel,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');
    return Container(
      key: const ValueKey('driver-on-way-card'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFE6EBF1)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: l.dpOpenProfile,
            child: InkWell(
              key: const ValueKey('driver-on-way-open-profile'),
              onTap: _openProfile,
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: dpGold,
                        ),
                        child: DriverPhotoAvatar(
                          driver: d,
                          radius: 28,
                          fallback: Text(
                            d.initial,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: dpNavy,
                            ),
                          ),
                        ),
                      ),
                      if (d.ratingLabel != null)
                        Positioned(
                          bottom: -9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: dpNavy,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '★ ${d.ratingLabel}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                d.displayFirstName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: dpNavy,
                                ),
                              ),
                            ),
                            if (widget.verified)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: dpBlue,
                                  semanticLabel: l.dpVerified,
                                ),
                              ),
                          ],
                        ),
                        if (d.tripCount != null && sinceYear != null)
                          Text(
                            l.dpTripsSince('${d.tripCount}', '$sinceYear'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: dpMuted,
                            ),
                          )
                        else if (d.tripCount != null)
                          Text(
                            l.driverTripCount(d.tripCount!),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: dpMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: dpMuted),
                ],
              ),
            ),
          ),
          if (d.plate != null || car.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (d.plate != null) SwedishPlate(text: d.plate!),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    [
                      if (car.isNotEmpty) car,
                      if ((d.vehicleColor ?? '').isNotEmpty) d.vehicleColor!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: dpNavy,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('waiting-call'),
                  onPressed: widget.onCall,
                  style: FilledButton.styleFrom(
                    backgroundColor: dpBlue,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.call_rounded, size: 20),
                  label: Text(
                    l.dpCall,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const ValueKey('waiting-chat'),
                  onPressed: () => _openChat(d.displayFirstName),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8F0FE),
                    foregroundColor: dpNavy,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.chat_rounded, size: 20, color: dpBlue),
                      if (unread > 0)
                        Positioned(
                          right: -3,
                          top: -3,
                          child: Semantics(
                            label: l.dpUnreadMessages,
                            child: Container(
                              key: const ValueKey('waiting-chat-unread'),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5484D),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  label: Text(
                    l.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (widget.onMore != null) ...[
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: widget.onMore,
                  tooltip: l.moreOptions,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A plate in the Swedish style: white, black border, a blue strip on the
/// left. Our own drawing, no image file.
class SwedishPlate extends StatelessWidget {
  const SwedishPlate({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('swedish-plate'),
    height: 30,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: const Color(0xFF1B1B1B), width: 1.4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          decoration: const BoxDecoration(
            color: Color(0xFF1C4FB8),
            borderRadius: BorderRadius.horizontal(left: Radius.circular(3.5)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Color(0xFF111111),
            ),
          ),
        ),
      ],
    ),
  );
}
