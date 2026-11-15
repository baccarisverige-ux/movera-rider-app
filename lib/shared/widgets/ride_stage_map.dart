import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'parkable_map.dart';

/// G25 step B (owner 2026-11-12 "GPS first, then all", BQ-V08): one Google
/// map for the whole trip on a phone.
///
/// Searching (Finding) and driver found / arriving / on board (Waiting)
/// are separate routes, and each used to build its own map: at "driver
/// found" the rider saw a blank surface, then a zoom jump. Now the map is
/// one widget under [mapKey]. Finding [RideStageSeat.handOn]s it just
/// before it pushes Waiting; Waiting's [RideStageMapSlot] takes it in its
/// first frame, so Flutter moves the same map (its platform view, its
/// controller and its camera) from one route to the other instead of
/// building a new one. A driver drop gives it back to Finding
/// ([RideStageSeat.reclaim]).
///
/// One seat holds the map at a time ([holder]); every slot listens to it,
/// so the slot that gives the map away and the one that takes it rebuild
/// in the same frame (a [GlobalKey] can only move that way). A screen that
/// was never handed the map (a reservation's live trip, a trip restored
/// at the root) builds its own map, as before. The web keeps one map per
/// screen: the page pools its maps itself ([ParkableMap]).
///
/// Map owners stay per screen: the screen that takes the map attaches its
/// own owner ([RideStageMapSlot.onAdopted]); the one that gives it away
/// detaches its own before.
class RideStageMap {
  RideStageMap._();

  static final RideStageMap instance = RideStageMap._();

  /// Whether the ride stages share one map on this platform: phones, where
  /// [ParkableMap] keeps a covered map (tests set it there).
  static bool get shares => ParkableMap.keepsMapWhileParked;

  /// The key of the one trip map ([CustomGoogleMap]).
  final GlobalKey mapKey = GlobalKey(debugLabel: 'ride-stage-map');

  /// The seat that shows the map, [_handedOn] while it is on its way to the
  /// next screen, or null.
  final RideStageMapHolder holder = RideStageMapHolder._();

  static final Object _handedOn = Object();

  GoogleMapController? _controller;

  /// Whether the trip map exists now (mounted somewhere, maybe still under
  /// the screen that is giving it away).
  bool get _mapExists => mapKey.currentContext != null;

  /// The trip map's controller, while that map exists.
  GoogleMapController? get controller => _mapExists ? _controller : null;
}

/// Who shows the trip map. Changes made while the tree builds or unmounts
/// are silent (nobody may rebuild then); a hand-over tells every slot.
class RideStageMapHolder extends ChangeNotifier {
  RideStageMapHolder._();

  Object? _value;
  Object? get value => _value;

  void _set(Object? next) {
    if (identical(next, _value)) return;
    _value = next;
    notifyListeners();
  }
}

/// A screen's place in [RideStageMap]: the token its slot holds the map
/// with. One per screen instance.
class RideStageSeat {
  RideStageSeat({this.startsMap = true});

  /// Whether this screen builds the trip map when none is on its way
  /// (Finding, the first trip screen). Waiting only takes a map handed to
  /// it; opened on its own (a reservation's live trip, a restored trip)
  /// it builds its own map as before.
  final bool startsMap;

  RideStageMap get _map => RideStageMap.instance;

  /// Whether this screen shows the trip map now.
  bool get holds => _map.holder.value == this;

  /// Whether this screen gave the trip map to the next one.
  bool _gaveAway = false;
  bool get handedOn => _gaveAway;

  /// The trip map was created on this seat ([CustomGoogleMap.onMapCreated]).
  void noteCreated(GoogleMapController controller) {
    if (holds) _map._controller = controller;
  }

  /// The next ride stage takes the map in its first frame: call right
  /// before pushing it, in the same event (no frame in between). Returns
  /// false (nothing done) where the stages do not share, or when this
  /// seat does not hold the map.
  bool handOn() {
    if (!RideStageMap.shares || !holds) return false;
    _gaveAway = true;
    _map.holder._set(RideStageMap._handedOn);
    return true;
  }

  /// This screen is on top again after it handed the map on: it takes the
  /// map back (from the screen leaving, in the same frame). Returns the
  /// controller of the map it got back, or null when a new map will be
  /// built (the old one is gone).
  GoogleMapController? reclaim() {
    if (!_gaveAway) return null;
    _gaveAway = false;
    final existing = _map.controller;
    if (!_map._mapExists) _map._controller = null;
    _map.holder._set(this);
    return existing;
  }

  /// A slot of this seat is mounting: it takes a map that is free or on
  /// its way. Returns whether it holds the map now.
  bool _take() {
    if (!RideStageMap.shares) return false;
    if (holds) return true;
    final current = _map.holder.value;
    if (current == null && !startsMap) return false;
    if (current != null && current != RideStageMap._handedOn) return false;
    if (!_map._mapExists) _map._controller = null;
    // No notify: this runs while the tree builds, and the seat that gave
    // the map away already rebuilds in this frame (it was notified).
    _map.holder._value = this;
    return true;
  }

  /// The screen is gone.
  void dispose() {
    if (holds) {
      // Unmount: nobody may be told now; the map goes with this screen.
      _map.holder._value = null;
    }
  }
}

/// Where a ride stage's map sits. It shows the trip map while its [seat]
/// holds it, [placeholder] after the seat handed it on, and the screen's
/// own map when the seat never got the trip map.
class RideStageMapSlot extends StatefulWidget {
  const RideStageMapSlot({
    super.key,
    required this.seat,
    required this.placeholder,
    required this.builder,
    this.onAdopted,
  });

  final RideStageSeat seat;
  final Widget placeholder;

  /// Builds the map: with [RideStageMap.mapKey] when it is the trip map,
  /// null for the screen's own map (its usual key).
  final Widget Function(BuildContext context, Key? sharedKey) builder;

  /// The slot took over a map that already exists (no onMapCreated comes):
  /// attach the screen's map owner and draw on it. Runs after the frame.
  final ValueChanged<GoogleMapController>? onAdopted;

  @override
  State<RideStageMapSlot> createState() => _RideStageMapSlotState();
}

class _RideStageMapSlotState extends State<RideStageMapSlot> {
  /// Whether this slot builds the trip map (else its screen's own map,
  /// or nothing once handed on).
  late bool _shared;

  @override
  void initState() {
    super.initState();
    final adopted = RideStageMap.instance._mapExists;
    _shared = widget.seat._take();
    if (_shared && adopted) _adoptAfterFrame();
    RideStageMap.instance.holder.addListener(_onHolder);
  }

  void _adoptAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = RideStageMap.instance.controller;
      if (!mounted || !widget.seat.holds || controller == null) return;
      widget.onAdopted?.call(controller);
    });
  }

  void _onHolder() {
    if (!mounted || !_shared) return;
    setState(() {});
  }

  @override
  void dispose() {
    RideStageMap.instance.holder.removeListener(_onHolder);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shared) return widget.builder(context, null);
    if (!widget.seat.holds) return widget.placeholder;
    return widget.builder(context, RideStageMap.instance.mapKey);
  }
}
