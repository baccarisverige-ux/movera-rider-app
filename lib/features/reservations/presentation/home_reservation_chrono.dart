import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:movera_rider/app/router/routes.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/app/router/home_history_observer.dart';
import 'package:movera_rider/core/constants/appassets.dart';
import 'package:movera_rider/features/reservations/application/reservation_controller.dart';
import 'package:movera_rider/features/reservations/domain/reservation.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_format.dart';
import 'package:movera_rider/features/reservations/presentation/reservation_live_ride.dart';
import 'package:movera_rider/features/reservations/presentation/upcoming_reservation.dart';
import 'package:movera_rider/shared/design_system/movera_sheet.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Home reservation timer. White face with a neutral ring; the ride's state is
/// carried by a small corner badge (shape + colour): check = driver assigned,
/// clock = booked (no driver yet), dots = searching, ! = no driver found.
class HomeReservationChrono extends StatefulWidget {
  const HomeReservationChrono({
    super.key,
    this.controller,
    this.now,
    this.onRebook,
    this.openRoute,
  });

  final ReservationController? controller;
  final DateTime Function()? now;

  /// Opens the scheduling flow so the rider can book a new time after a
  /// reservation timed out without a driver. When null, the "No driver
  /// found" sheet offers cancel only.
  final VoidCallback? onRebook;

  /// Wraps every page the chrono opens over Home (NAV-3). Home passes its
  /// park-the-map wrapper so its own Google Map is gone before the live
  /// ride's map mounts; two maps at once crash the tab on Flutter web.
  final Future<T?> Function<T>(Future<T?> Function() open)? openRoute;

  static const ink = Color(0xFF172127);
  static const confirmed = Color(0xFF1F9D5B);
  static const searching = Color(0xFFE08A2A);
  static const noDriver = Color(0xFFD64545);

  @override
  State<HomeReservationChrono> createState() => _HomeReservationChronoState();
}

class _HomeReservationChronoState extends State<HomeReservationChrono> {
  Timer? _tick;
  String? _openedLiveId;
  String? _promptedNoDriverId;
  bool _noDriverSheetOpen = false;

  @override
  void initState() {
    super.initState();
    moveraNavigationEpoch.addListener(_onNavigationChanged);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_onTick());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_onTick());
    });
  }

  Future<void> _onTick() async {
    await _reservations.startLiveIfDue(now: _now);
    if (mounted) setState(() {});
    _openLiveIfNeeded();
    _promptNoDriverIfNeeded();
  }

  bool get _routeIsCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  void _onNavigationChanged() {
    if (!mounted) return;
    // Scheduled rides can become live while Profile, Wallet or another child
    // route is open above Home. Never hijack that route; retry only after the
    // user returns to Home and Navigator has finished the pop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_routeIsCurrent) return;
      _openLiveIfNeeded();
      _promptNoDriverIfNeeded();
    });
  }

  bool _isNoDriverFound(Reservation ride) =>
      _reservations.isNoDriverFound(ride, now: _now);

  /// Surfaces the "No driver found" state once per reservation instead of
  /// leaving the rider watching a "Now" chrono indefinitely.
  void _promptNoDriverIfNeeded() {
    if (!mounted || !_routeIsCurrent || _noDriverSheetOpen) return;
    final ride = _nextRide();
    if (ride == null || !_isNoDriverFound(ride)) return;
    if (_promptedNoDriverId == ride.reservationId) return;
    _promptedNoDriverId = ride.reservationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_routeIsCurrent) {
        // A live ride opened first: ask again once Home is back.
        if (_promptedNoDriverId == ride.reservationId) {
          _promptedNoDriverId = null;
        }
        return;
      }
      unawaited(_showNoDriverFound(ride));
    });
  }

  Future<void> _showNoDriverFound(Reservation ride) async {
    if (_noDriverSheetOpen) return;
    _noDriverSheetOpen = true;
    try {
      final choice = await MoveraSheet.show<_NoDriverChoice>(
        context: context,
        builder: (sheetContext) => MoveraSheet(
          child: _NoDriverFoundSheet(canRebook: widget.onRebook != null),
        ),
      );
      if (!mounted || choice == null) return;
      final current = _reservations.byId(ride.reservationId);
      // A driver may have been assigned while the sheet was open.
      if (current == null || !_isNoDriverFound(current)) return;
      await _reservations.resolveNoDriverFound(ride.reservationId);
      if (!mounted) return;
      if (choice == _NoDriverChoice.rebook) widget.onRebook?.call();
    } finally {
      _noDriverSheetOpen = false;
    }
  }

  void _openLiveIfNeeded() {
    if (!mounted || !_routeIsCurrent) return;
    // rider-j8-10: the first ride whose driver is on the way, even when an
    // earlier one is still waiting to be resolved as "no driver found".
    final ride = _sortedUpcoming().where((r) => r.revealsDriver).firstOrNull;
    if (ride == null) return;
    if (_openedLiveId == ride.reservationId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_routeIsCurrent) return;
      unawaited(_openLiveRide(ride));
    });
  }

  Future<void> _openLiveRide(Reservation snapshot) async {
    if (!mounted || !_routeIsCurrent || _openedLiveId == snapshot.reservationId) return;
    // The snapshot can be a frame old (post-frame callback, stale tap). Only
    // open a ride that is still genuinely upcoming and still reveals its
    // driver — never one that has completed or been cancelled meanwhile.
    final ride = _reservations.byId(snapshot.reservationId);
    if (ride == null || !ride.status.isUpcoming || !ride.revealsDriver) return;
    _openedLiveId = ride.reservationId;
    await _open<void>(
      () => ReservationLiveRide.open(context, ride, controller: _reservations),
    );
    if (!mounted || _openedLiveId != ride.reservationId) return;
    _openedLiveId = null;
    _openLiveIfNeeded();
  }

  void _openRide(Reservation ride) {
    if (_isNoDriverFound(ride)) {
      _promptedNoDriverId = ride.reservationId;
      unawaited(_showNoDriverFound(ride));
      return;
    }
    if (ride.revealsDriver) {
      unawaited(_openLiveRide(ride));
      return;
    }
    unawaited(
      _open<void>(
        () => Navigator.of(context).push(
          RightToLeftTransition(
            UpcomingReservationPage(
              reservationId: ride.reservationId,
              controller: _reservations,
            ),
            settings: const RouteSettings(name: AppRoutes.reservationUpcoming),
          ),
        ),
      ),
    );
  }

  Future<T?> _open<T>(Future<T?> Function() open) {
    final wrap = widget.openRoute;
    return wrap == null ? open() : wrap<T>(open);
  }

  @override
  void dispose() {
    moveraNavigationEpoch.removeListener(_onNavigationChanged);
    _tick?.cancel();
    super.dispose();
  }

  ReservationController get _reservations =>
      widget.controller ?? AppScope.instance.reservations;

  List<Reservation> _sortedUpcoming() => [..._reservations.upcoming()]
    ..sort((a, b) => a.scheduledPickupAt.compareTo(b.scheduledPickupAt));

  /// The ride the chrono stands for: the earliest upcoming one, skipping a
  /// "no driver found" ride the rider was already shown when a later ride
  /// is waiting (rider-j8-10).
  Reservation? _nextRide() {
    final upcoming = _sortedUpcoming();
    if (upcoming.isEmpty) return null;
    return upcoming
            .where(
              (ride) =>
                  ride.reservationId != _promptedNoDriverId ||
                  !_isNoDriverFound(ride),
            )
            .firstOrNull ??
        upcoming.first;
  }

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _reservations,
      builder: (context, _) {
        final ride = _nextRide();
        if (ride == null) return const SizedBox.shrink();
        final noDriver = _isNoDriverFound(ride);
        // "Confirmed" (check) only when a driver is really on the ride:
        // status.hasDriver && driver != null. A booked ride with no driver
        // yet gets the clock, never the check.
        final (Color badgeColor, IconData badgeIcon, String badgeKey) = noDriver
            ? (
                HomeReservationChrono.noDriver,
                Icons.priority_high_rounded,
                'reservation-chrono-badge-no-driver',
              )
            : ride.driverAssigned
            ? (
                HomeReservationChrono.confirmed,
                Icons.check_rounded,
                'reservation-chrono-badge-confirmed',
              )
            : ride.isSearchingDriver
            ? (
                HomeReservationChrono.searching,
                Icons.more_horiz_rounded,
                'reservation-chrono-badge-searching',
              )
            : (
                const Color(0xFF6B757B),
                Icons.schedule_rounded,
                'reservation-chrono-badge-booked',
              );
        final parts = ReservationFormat.remainingParts(
          ride.scheduledPickupAt,
          now: _now,
        );
        final compact = ReservationFormat.remainingCompact(
          ride.scheduledPickupAt,
          now: _now,
        );
        // rider-j8-7: under a minute left, or a pickup already past (driver
        // arrived, trip under way), is "now", not "in Now".
        final due =
            ride.scheduledPickupAt.difference(_now).inSeconds < 60;
        return PointerInterceptor(
          child: Semantics(
            button: true,
            label: noDriver
                ? context.l10n.chronoNoDriverLabel
                : due
                ? context.l10n.reservationNow
                : context.l10n.reservationIn(compact),
            child: GestureDetector(
              onTap: () => _openRide(ride),
              child: SizedBox(
                width: 54,
                height: 54,
                child: Stack(
                  // The badge overhangs the disc by 6 px; the layout box and
                  // tap target stay 54x54 (the badge is decorative).
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x24000000),
                              blurRadius: 18,
                              offset: Offset(0, 7),
                            ),
                          ],
                        ),
                        child: CustomPaint(
                          painter: _ChronoFace(noDriver: noDriver),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  AppAssets.scheduleRideCar,
                                  height: 11,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox(height: 11),
                                ),
                                const SizedBox(height: 1),
                                if (noDriver)
                                  const Icon(
                                    Icons.person_off_outlined,
                                    key: Key('reservation-chrono-no-driver'),
                                    size: 18,
                                    color: HomeReservationChrono.noDriver,
                                  )
                                else
                                  // rider-u160: one line each, scaled down to
                                  // fit the disc at large text sizes and for
                                  // long words ('Maintenant').
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            parts.primary,
                                            maxLines: 1,
                                            softWrap: false,
                                            style: GoogleFonts.poppins(
                                              fontSize: parts.secondary == null
                                                  ? 13
                                                  : 11,
                                              fontWeight: FontWeight.w700,
                                              color: HomeReservationChrono.ink,
                                              height: 1,
                                            ),
                                          ),
                                          if (parts.secondary != null)
                                            Text(
                                              parts.secondary!,
                                              maxLines: 1,
                                              softWrap: false,
                                              style: GoogleFonts.poppins(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF6B757B),
                                                height: 1.1,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: ExcludeSemantics(
                        child: Container(
                          key: ValueKey<String>(badgeKey),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(badgeIcon, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _NoDriverChoice { rebook, cancel }

class _NoDriverFoundSheet extends StatelessWidget {
  const _NoDriverFoundSheet({required this.canRebook});

  final bool canRebook;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        key: const Key('reservation-no-driver-found'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.termNoDriverFound,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: HomeReservationChrono.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              canRebook
                  ? context.l10n.chronoNoDriverRebook
                  : context.l10n.chronoNoDriverCancel,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: const Color(0xFF6B757B),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            if (canRebook) ...[
              FilledButton(
                key: const Key('reservation-no-driver-rebook'),
                style: FilledButton.styleFrom(
                  backgroundColor: HomeReservationChrono.ink,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () =>
                    Navigator.of(context).pop(_NoDriverChoice.rebook),
                child: Text(context.l10n.rebook),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              key: const Key('reservation-no-driver-cancel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: HomeReservationChrono.ink,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () =>
                  Navigator.of(context).pop(_NoDriverChoice.cancel),
              child: Text(context.l10n.cancelReservation),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChronoFace extends CustomPainter {
  const _ChronoFace({required this.noDriver});

  /// Neutral ring for every state except "no driver found" (red). The ride's
  /// state lives in the corner badge, not in the ring colour.
  static const neutralRing = Color(0x55172127);

  final bool noDriver;

  Color get ring => noDriver ? HomeReservationChrono.noDriver : neutralRing;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final tick = Paint()
      ..color = const Color(0x33172127)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final angle = (i / 12) * math.pi * 2 - math.pi / 2;
      final outer = radius - 3.2;
      final inner = radius - (i % 3 == 0 ? 6.4 : 4.6);
      canvas.drawLine(
        center + Offset(math.cos(angle), math.sin(angle)) * inner,
        center + Offset(math.cos(angle), math.sin(angle)) * outer,
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChronoFace oldDelegate) =>
      oldDelegate.noDriver != noDriver;
}
