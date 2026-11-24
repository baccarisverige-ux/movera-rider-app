import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/messages/domain/chat_options.dart';
import 'package:movera_rider/features/messages/domain/messages.dart';
import 'package:movera_rider/app/deferred_screens.dart';
import 'package:movera_rider/features/driver_arriving/presentation/driver_photo_avatar.dart';
import 'package:movera_rider/features/driver_profile/presentation/driver_profile_sheet.dart';
import 'package:movera_rider/features/messages/application/messages_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/matched_driver.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

/// v0.18.155 "driver on the way" card (owner 2026-11-20 "Now build all";
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
    @visibleForTesting this.messages,
  });

  /// Test seam: the trip's conversation (production: the shared one of
  /// [rideId], on the app's chat transport).
  final MessagesController? messages;

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
  late MessagesController _messages = _controllerFor(widget.rideId);
  bool _opening = false;

  /// Driver messages the rider dismissed with a quick reply (by id).
  final Set<String> _dismissed = <String>{};

  bool get _ownsMessages => widget.messages == null;

  MessagesController _controllerFor(String? rideId) {
    final given = widget.messages;
    if (given != null) return given;
    final id = rideId?.trim() ?? '';
    return MessagesController.forRide(
      id,
      transport: id.isEmpty ? null : AppScope.instance.tripMessages,
    );
  }

  @override
  void initState() {
    super.initState();
    _messages.addListener(_changed);
    // Owner 2026-11-23: the server's quick replies (chat options) for the
    // inline message card.
    unawaited(_messages.loadOptions());
  }

  @override
  void didUpdateWidget(DriverOnWayCard old) {
    super.didUpdateWidget(old);
    if (old.rideId == widget.rideId) return;
    _messages.removeListener(_changed);
    if (_ownsMessages) _messages.dispose();
    _messages = _controllerFor(widget.rideId)..addListener(_changed);
    unawaited(_messages.loadOptions());
  }

  @override
  void dispose() {
    _messages.removeListener(_changed);
    if (_ownsMessages) _messages.dispose();
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
        chatScreen(
          driverName: name,
          rideId: widget.rideId,
          driver: widget.driver,
        ),
      ),
    );
  }

  /// The driver's latest unread message, unless dismissed.
  ChatMessage? get _inlineMessage {
    if (_messages.unreadCount == 0) return null;
    for (final m in _messages.messages.reversed) {
      if (m.sender == ChatMessageSender.rider || m.isSystem) continue;
      final id = m.messageId ?? m.localId ?? m.text;
      return _dismissed.contains(id) ? null : m;
    }
    return null;
  }

  void _reply(ChatMessage message, ChatQuickReply reply) {
    if (!_messages.sendQuickReply(reply)) return;
    setState(
      () =>
          _dismissed.add(message.messageId ?? message.localId ?? message.text),
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
    final carLine = [
      if (car.isNotEmpty) car,
      if ((d.vehicleColor ?? '').isNotEmpty) d.vehicleColor!,
    ].join(' · ');
    final inline = _inlineMessage;
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: l.dpOpenProfile,
                  child: InkWell(
                    key: const ValueKey('driver-on-way-open-profile'),
                    onTap: _openProfile,
                    borderRadius: BorderRadius.circular(14),
                    child: Row(
                      children: [
                        DriverRatedPhoto(driver: d, radius: 30),
                        const SizedBox(width: 12),
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
                                  l.dpTripsSince(
                                    '${d.tripCount}',
                                    '$sinceYear',
                                  ),
                                  maxLines: 2,
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
                      ],
                    ),
                  ),
                ),
              ),
              if (d.plate != null || carLine.isNotEmpty) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (d.plate != null)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SwedishPlate(text: d.plate!),
                        ),
                      if (carLine.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          carLine,
                          maxLines: 2,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: dpNavy,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Same spoken label as the old block's Call chip.
              _RoundAction(
                buttonKey: const ValueKey('waiting-call'),
                semantics: l.callDriver,
                label: l.dpCall,
                icon: const Icon(Icons.call_outlined, size: 22, color: dpNavy),
                onTap: widget.onCall,
              ),
              const SizedBox(width: 18),
              // Owner 2026-11-23: "Chatt"; screen readers hear the full word.
              _RoundAction(
                buttonKey: const ValueKey('waiting-chat'),
                semantics: l.message,
                label: l.dpChat,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 21,
                      color: dpNavy,
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -6,
                        top: -8,
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
                onTap: () => _openChat(d.displayFirstName),
              ),
              const Spacer(),
              if (widget.onMore != null)
                // Same label as the old block's ⋯ chip (screen readers and
                // the route tests find it by this label).
                _RoundAction(
                  buttonKey: const ValueKey('waiting-more'),
                  semantics: l.moreOptions,
                  tooltip: l.moreOptions,
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    size: 24,
                    color: dpNavy,
                  ),
                  onTap: widget.onMore!,
                ),
            ],
          ),
          if (inline != null) ...[
            const SizedBox(height: 14),
            DriverMessageCard(
              from: l.dpFromDriver(d.displayFirstName),
              text: inline.text,
              replies: _messages.canSendMessages
                  ? _messages.options.shownQuickReplies
                  : const [],
              language: l.localeName,
              onOpen: () => _openChat(d.displayFirstName),
              onReply: (reply) => _reply(inline, reply),
            ),
          ],
        ],
      ),
    );
  }
}

/// A round white button with a hair border and an optional small label
/// under it (Ring / Chatt / ⋯, owner 2026-11-23 B2).
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.buttonKey,
    required this.semantics,
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
  });

  final Key buttonKey;
  final String semantics;
  final String? label;
  final String? tooltip;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: Color(0xFFE7EBEE))),
        child: InkWell(
          key: buttonKey,
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(dimension: 48, child: Center(child: icon)),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tooltip != null)
          Tooltip(message: tooltip!, child: button)
        else
          button,
        if (label != null) ...[
          const SizedBox(height: 6),
          ExcludeSemantics(
            child: Text(
              label!,
              maxLines: 1,
              style: const TextStyle(fontSize: 13, color: dpNavy),
            ),
          ),
        ],
      ],
    );
  }
}

/// The driver's photo, plain round (no ring), with the ★ rating badge.
class DriverRatedPhoto extends StatelessWidget {
  const DriverRatedPhoto({
    super.key,
    required this.driver,
    this.radius = 30,
    this.photoKey,
  });

  final MatchedDriver driver;
  final double radius;
  final Key? photoKey;

  @override
  Widget build(BuildContext context) {
    final d = driver;
    return Padding(
      padding: EdgeInsets.only(bottom: d.ratingLabel != null ? 8 : 0),
      child: Stack(
        key: photoKey,
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          DriverPhotoAvatar(
            driver: d,
            radius: radius,
            fallback: Text(
              d.initial,
              style: TextStyle(
                fontSize: radius * 0.6,
                fontWeight: FontWeight.w700,
                color: dpNavy,
              ),
            ),
          ),
          if (d.ratingLabel != null)
            Positioned(
              bottom: -9,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: dpNavy,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Colors.white, width: 1.5),
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
    );
  }
}

/// Owner 2026-11-23: a new driver message, inline under the buttons — the
/// driver app's TripChatCard look (#202A30, `Från <name>`, two lines, an
/// arrow that opens the chat) with the server's quick replies as dark
/// chips that send and dismiss.
class DriverMessageCard extends StatelessWidget {
  const DriverMessageCard({
    super.key,
    required this.from,
    required this.text,
    required this.replies,
    required this.language,
    required this.onOpen,
    required this.onReply,
  });

  final String from;
  final String text;
  final List<ChatQuickReply> replies;
  final String language;
  final VoidCallback onOpen;
  final ValueChanged<ChatQuickReply> onReply;

  static const Color background = Color(0xFF202A30);

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('driver-msg-card'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('driver-msg-open'),
            onTap: onOpen,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        from,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFAEB7BE),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          if (replies.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final reply in replies)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: const Color(0xFF34404A),
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: () => onReply(reply),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              reply.textIn(language),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A Swedish plate in the EU style (owner 2026-11-23): white with a black
/// border, the blue EU strip on the left with the ring of stars and "S".
/// Our own drawing, no image file.
class SwedishPlate extends StatelessWidget {
  const SwedishPlate({super.key, required this.text, this.small = false});
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final h = small ? 22.0 : 30.0;
    return Container(
      key: const ValueKey('swedish-plate'),
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(small ? 4 : 5),
        border: Border.all(color: const Color(0xFF111111), width: 1.4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: h * 0.5,
            decoration: BoxDecoration(
              color: const Color(0xFF1C3FAA),
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(small ? 2.5 : 3.5),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SizedBox.square(
                  key: const ValueKey('eu-stars'),
                  dimension: h * 0.36,
                  child: const CustomPaint(painter: _EuStars()),
                ),
                Text(
                  'S',
                  style: TextStyle(
                    fontSize: h * 0.3,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: small ? 6 : 9),
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: small ? 12 : 16,
                fontWeight: FontWeight.w700,
                letterSpacing: small ? 0.8 : 1.4,
                color: const Color(0xFF111111),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The EU ring of twelve yellow stars (dots at this size).
class _EuStars extends CustomPainter {
  const _EuStars();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.42;
    final p = Paint()..color = const Color(0xFFFFCC00);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawCircle(
        c + Offset(math.cos(a) * r, math.sin(a) * r),
        size.shortestSide * 0.07,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
