import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/adjust_pickup.dart';
import 'package:movera_rider/features/active_ride/application/live_location_share.dart';
import 'package:movera_rider/features/finding_driver/presentation/adjust_pickup_banner.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/design_system/tokens.dart';

/// One GPS fix: the point and its accuracy (m).
typedef RideFix = ({GeoPoint point, double? accuracyMeters});

/// The phone's fix, only when location is already allowed (this widget
/// never asks for the permission itself). Null: no fix now.
Future<RideFix?> currentRideFix([
  LocationRepository repo = const LocationRepository(),
]) async {
  try {
    final permission = await repo.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    final at = await repo.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 6),
      ),
    );
    return (
      point: GeoPoint(at.latitude, at.longitude),
      accuracyMeters: at.accuracy,
    );
  } catch (_) {
    return null;
  }
}

/// Contract v0.18.144 (owner 2026-11-20; approved mockup screens 6 and 7):
/// the ride screen's adjust-pickup banner and, while the driver comes, the
/// rider's "Share my location" switch. Lives only while the ride screen is
/// open: the GPS read and the sends stop with it (server CPU, audits/load).
class RideLocationTools extends StatefulWidget {
  const RideLocationTools({
    super.key,
    required this.tripId,
    required this.phase,
    required this.pickup,
    required this.settings,
    required this.senders,
    required this.onAdjust,
    this.bookedPickup,
    this.maxMoveMeters,
    this.driverName,
    this.fix = currentRideFix,
    this.bannerAllowed = true,
  });

  /// False where the pickup cannot move now (the driver has arrived):
  /// no banner (contract: not at arrived).
  final bool bannerAllowed;

  final String? tripId;
  final AdjustPickupPhase phase;
  final GeoPoint pickup;
  final GeoPoint? bookedPickup;
  final int? maxMoveMeters;
  final String? driverName;
  final LiveLocationSettings settings;

  /// Makes the live sender (`liveLocationSenders(api)`).
  final LiveLocationSenders senders;

  /// Moves the pickup to the point (the screen's own path: the v0.18.143
  /// route change while searching, `PATCH { pickup }` after accept). True
  /// when it moved.
  final Future<bool> Function(GeoPoint to) onAdjust;
  final Future<RideFix?> Function() fix;

  @override
  State<RideLocationTools> createState() => RideLocationToolsState();
}

@visibleForTesting
class RideLocationToolsState extends State<RideLocationTools>
    with WidgetsBindingObserver {
  Timer? _timer;
  RideFix? _fix;
  DateTime? _fixAt;
  bool _lastReadFailed = false;
  bool _away = false;

  /// The pickup (as lat,lng text) the banner was closed or used for.
  String? _closedFor;
  String get _pickupKey =>
      '${widget.pickup.latitude},${widget.pickup.longitude}';
  bool _busy = false;
  bool _sharing = false;
  bool _zoneOff = false;
  LiveLocationSender? _sender;

  Duration get _every => Duration(seconds: widget.settings.sendEverySeconds);

  /// Whether the banner can show at all (0 m = off in the zone).
  bool get _bannerPossible =>
      widget.bannerAllowed && widget.settings.adjustPickupMeters > 0;

  /// Battery: the GPS is read every [_every] while sharing (the sender
  /// reuses that one fix), every 30 s while only the banner can show, and
  /// not at all when neither can.
  Duration? get _readEvery => _away
      ? null
      : _sharing
      ? _every
      : _bannerPossible
      ? bannerReadEvery
      : null;

  @visibleForTesting
  static const bannerReadEvery = Duration(seconds: 30);

  Duration? _armedFor;

  void _arm() {
    final every = _readEvery;
    if (every == _armedFor && (_timer != null || every == null)) return;
    _timer?.cancel();
    _timer = null;
    _armedFor = every;
    if (every == null) return;
    unawaited(_read());
    _timer = Timer.periodic(every, (_) => unawaited(_read()));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arm();
  }

  /// Hidden or paused: no GPS read and no send; sharing turns off (it comes
  /// back only on a tap). Back in front: the banner's reads start again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (away == _away && state != AppLifecycleState.resumed) return;
    _away = away;
    if (away && _sharing) {
      unawaited(_setSharing(false));
    } else {
      _arm();
    }
  }

  /// The last fix when it is fresh enough for the banner (30 s reads: at
  /// most 2 x 30 s old, and the last read did not fail).
  RideFix? get freshFixForBanner {
    final at = _fixAt;
    if (_lastReadFailed || at == null) return null;
    final every = _readEvery ?? bannerReadEvery;
    return DateTime.now().difference(at) > every * 2 ? null : _fix;
  }

  /// The fix the sender may use: a successful read at most 2 × the send
  /// interval old; else null (then nothing is sent).
  GeoPoint? get freshPoint {
    final at = _fixAt;
    if (_lastReadFailed || at == null) return null;
    if (DateTime.now().difference(at) > _every * 2) return null;
    return _fix?.point;
  }

  @override
  void didUpdateWidget(covariant RideLocationTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    _arm();
    // Sharing is only while the driver comes (accept until pickup).
    if (widget.phase != AdjustPickupPhase.driverComing && _sharing) {
      unawaited(_setSharing(false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    // Ride screen closed (pickup, ride end, cancel): sharing stops.
    unawaited(_sender?.stop());
    super.dispose();
  }

  Future<void> _read() async {
    final fix = await widget.fix();
    if (!mounted) return;
    if (fix == null) {
      // setState: a banner built on the old fix hides.
      setState(() => _lastReadFailed = true);
      return;
    }
    setState(() {
      _fix = fix;
      _fixAt = DateTime.now();
      _lastReadFailed = false;
    });
  }

  int? get _meters {
    // The banner follows the same freshness rule as the sender.
    final fix = freshFixForBanner;
    if (fix == null || !_bannerPossible || _closedFor == _pickupKey) {
      return null;
    }
    return AdjustPickup.metersToShow(
      phase: widget.phase,
      gps: fix.point,
      accuracyMeters: fix.accuracyMeters,
      pickup: widget.pickup,
      thresholdMeters: widget.settings.adjustPickupMeters,
      bookedPickup: widget.bookedPickup,
      maxMoveMeters: widget.maxMoveMeters,
    );
  }

  Future<void> _adjust() async {
    final fix = freshFixForBanner;
    if (fix == null || _busy) return;
    setState(() => _busy = true);
    final moved = await widget.onAdjust(fix.point);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (moved) _closedFor = _pickupKey;
    });
    if (moved) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.l10n.liveAdjustPickupDone)),
        );
    }
  }

  /// Each _setSharing call takes a new number; a call that finds a newer
  /// one after an await gives up, so overlapping taps leave one sender.
  int _shareGen = 0;

  /// The live sender (tests).
  @visibleForTesting
  LiveLocationSender? get sender => _sender;

  /// The switch as a tap sets it (tests: an off while an on still waits
  /// for the GPS, which a tap cannot do while the switch shows off).
  @visibleForTesting
  Future<void> debugSetSharing(bool on) => _setSharing(on);

  Future<void> _setSharing(bool on) async {
    final id = widget.tripId;
    if (id == null) return;
    final gen = ++_shareGen;
    if (on) {
      final first = await widget.fix();
      if (gen != _shareGen || !mounted) return;
      // The screen moved past "driver coming", the app went away, or no
      // location permission / no fix: the switch stays off.
      if (_away ||
          widget.phase != AdjustPickupPhase.driverComing ||
          first == null) {
        final old = _sender;
        _sender = null;
        await old?.stop();
        if (gen != _shareGen || !mounted) return;
        setState(() => _sharing = false);
        _arm();
        return;
      }
      // The older sender (a double tap) stops right before the new one.
      final old = _sender;
      _sender = null;
      await old?.stop(tellServer: false);
      if (gen != _shareGen || !mounted) return;
      setState(() {
        _fix = first;
        _fixAt = DateTime.now();
        _lastReadFailed = false;
      });
      _sender = widget.senders(
        tripId: id,
        every: _every,
        position: () async => freshPoint,
        onStopped: (why) {
          if (!mounted) return;
          setState(() {
            _sharing = false;
            if (why == LiveShareStop.zoneOff) _zoneOff = true;
          });
          _arm();
        },
      )..start();
    } else {
      final sender = _sender;
      _sender = null;
      await sender?.stop();
      if (gen != _shareGen) return;
    }
    if (mounted) setState(() => _sharing = on);
    _arm();
  }

  @override
  Widget build(BuildContext context) {
    final meters = _meters;
    final showShare =
        widget.settings.share &&
        !_zoneOff &&
        widget.tripId != null &&
        widget.phase == AdjustPickupPhase.driverComing;
    if (meters == null && !showShare) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (meters != null) ...[
          AdjustPickupBanner(
            meters: meters,
            busy: _busy,
            onAdjust: _adjust,
            onClose: () => setState(() => _closedFor = _pickupKey),
          ),
          const SizedBox(height: 12),
        ],
        if (showShare) ...[
          ShareLocationCard(
            on: _sharing,
            driverName: widget.driverName,
            onChanged: (on) => unawaited(_setSharing(on)),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// The rider's "Share my location" switch (approved mockup screen 7).
class ShareLocationCard extends StatelessWidget {
  const ShareLocationCard({
    super.key,
    required this.on,
    required this.onChanged,
    this.driverName,
  });

  final bool on;
  final String? driverName;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = (driverName ?? '').trim();
    return Container(
      key: const Key('share-location-card'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MoveraTokens.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.my_location_rounded, color: MoveraTokens.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.liveShareSwitch,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: MoveraTokens.ink,
                  ),
                ),
                if (name.isNotEmpty)
                  Text(
                    l10n.liveRiderShareBody(name),
                    style: const TextStyle(color: MoveraTokens.muted),
                  ),
                Text(
                  l10n.livePrivacyNote,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MoveraTokens.subtle,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: const Key('share-location-switch'),
            value: on,
            activeTrackColor: MoveraTokens.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
