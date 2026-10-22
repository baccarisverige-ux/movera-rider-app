import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/maps/camera_tilt.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';

/// What the app knows about one live map: its viewport, where its camera
/// is, whether it leans with zoom, and whether the rider is holding it.
///
/// The camera rules are the driver app's: tilt follows zoom
/// ([tiltForZoom]), the camera never moves under a finger ([touching]),
/// a running ease is retargeted instead of restarted, and an ease that
/// only tilts keeps the latest target and zoom on every frame.
class MapView {
  /// Map viewport in logical pixels, inside the map's own padding.
  Size? size;

  /// Latest camera pose: the one the map reported or the app last sent.
  CameraPosition? pose;

  /// False for screens that read a ground point from a screen-centred pin
  /// with flat-map maths (Set pickup, Confirm pickup spot): they stay flat.
  bool tiltWithZoom = true;

  /// False where the engine ignores tilt (raster maps on the web): the
  /// camera keeps the plain bounds fit there.
  bool supportsTilt = true;

  /// The plugin's map id on the web, for the gesture layer; null in tests.
  int? mapId;

  /// Bumped by every camera command and by every touch. A stepped ease
  /// stops as soon as it changes, so an older pose never lands after a
  /// newer command and nothing moves under a finger.
  int generation = 0;

  /// True while a stepped ease is running.
  bool easing = false;

  /// A finger (or mouse button) is down on the map. Nothing the app asks
  /// for moves the camera meanwhile.
  bool get touching => _touching;
  bool _touching = false;

  /// When the rider last moved the map by hand (pan, pinch, wheel); null
  /// once the app recentred it.
  DateTime? get movedByHandAt => _movedByHandAt;
  DateTime? _movedByHandAt;
  set movedByHandAt(DateTime? value) {
    _movedByHandAt = value;
    // rider-j8-12: camera reports after a hand move are the rider's, not
    // late echoes of a flight that landed before it.
    if (value != null) _landedAt = null;
  }

  /// How long a map the rider moved by hand stays theirs: follow updates
  /// (the driver's position on the trip map, a late location fix on Home)
  /// wait this long after the last gesture, like the driver app's trip
  /// camera. A recenter takes the map back at once.
  static const Duration followHold = Duration(seconds: 12);

  /// Clock for [followHold] (tests replace it).
  static DateTime Function() now = DateTime.now;

  /// Whether a follow update must leave the map alone.
  bool get heldByRider {
    if (_touching) return true;
    final at = movedByHandAt;
    return at != null && now().difference(at) < followHold;
  }

  /// Tilt for [zoom] on this map (0 where it stays flat).
  double tiltFor(double zoom) =>
      tiltWithZoom && supportsTilt ? tiltForZoom(zoom) : 0;

  set touching(bool value) {
    if (_touching == value) return;
    _touching = value;
    // An ease (a recenter glide, the tilt settling after a pinch) stops
    // under the new finger.
    if (value) interrupt();
  }

  /// Stops any ease still running on this map.
  void interrupt() {
    generation += 1;
    easing = false;
    // rider-j8-12: a touch or a newer command ends the landed flight's echo
    // window; the camera reports after it are new poses.
    _landedAt = null;
    _goal = null;
    _tiltEase = null;
    _flight = null;
    if (_jsFlight) {
      _jsFlight = false;
      final id = mapId;
      // rider-j8-13: while the flight ran, the map's camera reports were
      // ignored, so [pose] is still where it started. Take the camera's
      // live pose; when the layer cannot say, the pose is unknown and the
      // next command or camera report sets it.
      if (id != null) pose = RiderMapBridge.cancelFlight(id);
    }
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  CameraPosition? _goal;
  Duration _goalDuration = cameraEaseDuration;

  /// The running flight's clock: its length and how far along it is
  /// (null while the glide is a damped follow).
  Duration? _flight;
  int _flownMicros = 0;

  /// True while the web layer flies the camera on the browser's frame
  /// clock (requestAnimationFrame) instead of the Dart loop.
  bool _jsFlight = false;

  /// When a web flight last landed. The map's "camera moved" echoes of its
  /// frames can arrive after it lands; for a short while after, an echo
  /// that is not the landing pose is late and must not become [pose]
  /// (the tilt settle would fly the camera back to it).
  DateTime? _landedAt;

  /// Whether [reported] is a late echo of a flight that just landed.
  bool isLateEcho(CameraPosition reported) {
    final landed = _landedAt;
    final current = pose;
    if (landed == null || current == null) return false;
    if (now().difference(landed) > cameraEchoGrace) return false;
    return !_settled(reported, current);
  }
  Completer<void>? _done;
  ({double target, int generation, Completer<void> done})? _tiltEase;
}

final Expando<MapView> _views = Expando<MapView>('MapView');

/// The [MapView] of [controller], created on first use.
MapView mapViewOf(GoogleMapController controller) =>
    _views[controller] ??= MapView();

/// How long a camera ease takes (its time constant; the motion is a damped
/// approach that a newer goal retargets, never restarts).
const Duration cameraEaseDuration = Duration(milliseconds: 450);

/// A recenter (a flight) takes this long, start to rest. Unlike the
/// damped follow glide, whose tail crept on for 4-5 s (up to the frame
/// cap) before it settled, a flight runs on the clock: it eases in and out
/// over this time ([flightEase]) and lands on its goal on time.
const Duration cameraFlightDuration = Duration(milliseconds: 1000);

/// Glides at least this long are flights ([cameraFlightDuration]); shorter
/// ones are the damped follow glide.
const Duration _flightThreshold = Duration(milliseconds: 600);

/// How long after a web flight lands its late camera echoes are ignored.
const Duration cameraEchoGrace = Duration(milliseconds: 600);

/// Interval between the poses of a stepped ease (about 60 fps).
const Duration cameraEaseFrame = Duration(milliseconds: 16);

/// The tilt that follows the rider's own zoom eases in this long.
const Duration cameraTiltFlight = Duration(milliseconds: 350);

/// A command that waits longer than this lands on its goal.
const int _maxEaseFrames = 240;

bool _settled(CameraPosition a, CameraPosition b) =>
    (a.target.latitude - b.target.latitude).abs() <= 0.00002 &&
    (a.target.longitude - b.target.longitude).abs() <= 0.00002 &&
    _angleDelta(a.bearing, b.bearing).abs() <= 0.4 &&
    (a.zoom - b.zoom).abs() <= 0.02 &&
    (a.tilt - b.tilt).abs() <= 0.4;

double _angleDelta(double from, double to) => (to - from + 540) % 360 - 180;

/// One frame ([dtMicros]) of a damped approach from [from] to [to], as the
/// driver's follow camera: position, zoom and heading each close a fixed
/// share of the gap per unit of time. The tilt rides with the zoom on the
/// [view]'s curve, so it is the zoom's tilt on every frame; a tilt off the
/// curve (a hand tilt) is carried along and closes like the zoom.
CameraPosition _approach(
  MapView view,
  CameraPosition from,
  CameraPosition to,
  int dtMicros,
  Duration duration,
) {
  final span = math.max(200000, duration.inMicroseconds);
  double step(num tau) => 1 - math.exp(-dtMicros / tau);
  final pos = step(span * 0.70);
  final bearing = step(span * 1.60);
  final zoom = step(span * 1.10);
  final nextZoom = from.zoom + (to.zoom - from.zoom) * zoom;
  final fromOffset = from.tilt - view.tiltFor(from.zoom);
  final toOffset = to.tilt - view.tiltFor(to.zoom);
  final tilt = (view.tiltFor(nextZoom) + fromOffset + (toOffset - fromOffset) * zoom)
      .clamp(0.0, maxTiltForZoom(nextZoom));
  return CameraPosition(
    target: LatLng(
      from.target.latitude + (to.target.latitude - from.target.latitude) * pos,
      from.target.longitude +
          (to.target.longitude - from.target.longitude) * pos,
    ),
    zoom: nextZoom,
    bearing: (from.bearing + _angleDelta(from.bearing, to.bearing) * bearing +
            360) %
        360,
    tilt: tilt,
  );
}

/// Speed of a flight's first and last phase as a share of its middle
/// phase (owner: 20 % less).
const double slowPhaseSpeed = .8;

/// Where the middle phase blends in and out (shares of the flight). The
/// three phases are a third each; each blend is a short smoothstep centred
/// on the phase edge, so the speed changes without a cut.
const double _riseFrom = .25, _riseTo = .40, _fallFrom = .60, _fallTo = .75;

/// Integral 0..[x] of the middle-phase bump (0 in the slow phases, 1 in
/// the middle one, smoothstep blends between).
double _bumpIntegral(double x) {
  const w = _riseTo - _riseFrom;
  // Integral of smoothstep(u) is u^3 - u^4 / 2.
  double rise(double u) => w * (u * u * u - u * u * u * u / 2);
  if (x <= _riseFrom) return 0;
  if (x <= _riseTo) return rise((x - _riseFrom) / w);
  final full = rise(1);
  if (x <= _fallFrom) return full + (x - _riseTo);
  final plateau = full + (_fallFrom - _riseTo);
  if (x <= _fallTo) {
    final u = (x - _fallFrom) / w;
    return plateau + w * u - rise(u);
  }
  return plateau + w - full;
}

/// Eased progress of a flight at time [t] (0..1), the owner's locate glide:
/// three phases of equal length, each at an even speed, the first and last
/// at [slowPhaseSpeed] of the middle one, joined by short smooth blends.
/// The camera leaves at once and lands at the slow phase's speed: no slow
/// creep at the start, no cut between the phases.
double flightEase(double t) {
  final x = t.clamp(0.0, 1.0);
  const total = slowPhaseSpeed + (1 - slowPhaseSpeed) * .35;
  return (slowPhaseSpeed * x + (1 - slowPhaseSpeed) * _bumpIntegral(x)) /
      total;
}

/// The pan's share of the remaining way when the zoom covers [zoomShare]
/// of a zoom change [dz]: a ground step looks 2^zoom times bigger on
/// screen, so a pan moving in step with the zoom would crawl while zoomed
/// out and rush once zoomed in. This keeps its speed even on screen.
double _panShare(double zoomShare, double dz) {
  if (dz.abs() < 1e-3) return zoomShare;
  final k = zoomShare.clamp(0.0, 1.0);
  return (1 - math.pow(2, -dz * k)) / (1 - math.pow(2, -dz));
}

/// [share] (0..1) of the way from [from] to [to]; the tilt rides the zoom
/// on the [view]'s curve as in [_approach].
CameraPosition _blend(
  MapView view,
  CameraPosition from,
  CameraPosition to,
  double share, {
  double? panShare,
}) {
  final k = share.clamp(0.0, 1.0);
  final p = (panShare ?? share).clamp(0.0, 1.0);
  final nextZoom = from.zoom + (to.zoom - from.zoom) * k;
  final fromOffset = from.tilt - view.tiltFor(from.zoom);
  final toOffset = to.tilt - view.tiltFor(to.zoom);
  final tilt = (view.tiltFor(nextZoom) + fromOffset + (toOffset - fromOffset) * k)
      .clamp(0.0, maxTiltForZoom(nextZoom));
  return CameraPosition(
    target: LatLng(
      from.target.latitude + (to.target.latitude - from.target.latitude) * p,
      from.target.longitude + (to.target.longitude - from.target.longitude) * p,
    ),
    zoom: nextZoom,
    bearing: (from.bearing + _angleDelta(from.bearing, to.bearing) * k + 360) %
        360,
    tilt: tilt,
  );
}

Future<void> _send(
  GoogleMapController controller,
  MapView view,
  CameraPosition pose,
) {
  view.pose = pose;
  final id = view.mapId;
  // On the web the plugin pans with a glide; one ease frame must land now.
  if (id != null) RiderMapBridge.claim(id);
  return controller.moveCamera(CameraUpdate.newCameraPosition(pose));
}

/// Moves [controller]'s camera to [to] continuously: one damped glide of
/// small instant camera frames (about 60 per second), on phones and on the
/// web alike, like the driver app.
///
/// A call while a glide is running retargets it: the camera keeps its
/// speed and turns towards the newer goal, instead of stopping and
/// re-accelerating from rest (which stuttered when the trip map refitted
/// on every driver position). Nothing moves while a finger is on the map.
Future<void> easeCameraTo(
  GoogleMapController controller,
  CameraPosition to, {
  Duration duration = cameraEaseDuration,
}) {
  final view = mapViewOf(controller);
  if (view.touching) return Future<void>.value();
  final running = view._done;
  // rider-j8-15: a flight (a recenter) during a follow glide starts afresh
  // below, so it runs on the browser's frame clock on the web and gets its
  // own frame budget instead of the follow glide's remaining frames.
  final startsFlight =
      view._flight == null && duration >= _flightThreshold;
  if (view.easing &&
      view._goal != null &&
      running != null &&
      !startsFlight) {
    view._goal = to;
    view._goalDuration = duration;
    final id = view.mapId;
    if (view._jsFlight && id != null) {
      RiderMapBridge.retarget(id, to);
      return running.future;
    }
    // A newer goal joins a running flight on its clock (a fresh fix after a
    // recenter, a follow update), so the flight still lands on time.
    return running.future;
  }
  view.interrupt();
  final from = view.pose;
  if (from == null) {
    return _send(controller, view, to);
  }
  final generation = view.generation;
  final done = view._done = Completer<void>();
  view._goal = to;
  view._goalDuration = duration;
  view._flight = duration >= _flightThreshold ? duration : null;
  view._flownMicros = 0;
  view.easing = true;
  // On the web a flight runs in the gesture layer on the browser's frame
  // clock: one camera move per painted frame, so it never stutters on a
  // Dart timer (Safari). Follow glides and other platforms step here.
  final id = view.mapId;
  final js = view._flight == null || id == null
      ? null
      : RiderMapBridge.flight(id, to, duration);
  if (js != null) {
    view._jsFlight = true;
    unawaited(_jsGlide(view, generation, done, js));
    return done.future;
  }
  unawaited(_glide(controller, view, generation, done));
  return done.future;
}

Future<void> _jsGlide(
  MapView view,
  int generation,
  Completer<void> done,
  Future<bool> landed,
) async {
  var arrived = false;
  try {
    arrived = await landed;
  } catch (_) {
    // The map went away mid-flight.
  } finally {
    if (view.generation == generation) {
      // The layer landed exactly on the latest goal.
      if (arrived && view._goal != null) {
        view.pose = view._goal;
        view._landedAt = MapView.now();
      }
      view._jsFlight = false;
      view.easing = false;
      view._goal = null;
      view._flight = null;
      if (identical(view._done, done)) view._done = null;
    }
    if (!done.isCompleted) done.complete();
  }
}

Future<void> _glide(
  GoogleMapController controller,
  MapView view,
  int generation,
  Completer<void> done,
) async {
  try {
    var dt = cameraEaseFrame.inMicroseconds;
    for (var frame = 0; ; frame++) {
      if (view.generation != generation) return;
      final goal = view._goal;
      final from = view.pose;
      if (goal == null || from == null) return;
      final flight = view._flight;
      final CameraPosition next;
      final bool last;
      if (flight != null) {
        // On the clock: each frame closes the share of the remaining gap
        // that the eased curve covers in it, so a fixed goal follows the
        // curve exactly and a moved one is turned to smoothly.
        final span = flight.inMicroseconds;
        final before = flightEase(view._flownMicros / span);
        view._flownMicros += frame == 0 ? cameraEaseFrame.inMicroseconds : dt;
        final after = flightEase(view._flownMicros / span);
        last = after >= 1 || frame >= _maxEaseFrames;
        final share = (after - before) / (1 - before);
        next = last
            ? goal
            : _blend(
                view,
                from,
                goal,
                share,
                panShare: _panShare(share, goal.zoom - from.zoom),
              );
      } else {
        last = frame >= _maxEaseFrames || _settled(from, goal);
        next = last
            ? goal
            : _approach(view, from, goal, dt, view._goalDuration);
      }
      await _send(controller, view, next);
      if (last || view.generation != generation) return;
      final started = DateTime.now();
      await Future<void>.delayed(cameraEaseFrame);
      // Real time, but never less than one frame, so a glide also ends
      // where the clock barely moves (tests, fast frames).
      dt = math.max(
        cameraEaseFrame.inMicroseconds,
        DateTime.now().difference(started).inMicroseconds,
      );
    }
  } catch (_) {
    // The map went away mid-glide; nothing to correct.
  } finally {
    if (view.generation == generation) {
      view.easing = false;
      view._goal = null;
      view._flight = null;
      if (identical(view._done, done)) view._done = null;
    }
    if (!done.isCompleted) done.complete();
  }
}

/// Tilts [controller]'s camera to [tilt] where the rider left it, in one
/// short eased move: every frame keeps the camera's latest target, zoom
/// and heading, so the ease can never pull the zoom or position back.
///
/// Maps reports idle between the ease's own frames, so the same request
/// arrives again while it runs: that one joins the running ease instead of
/// restarting it (a restart re-accelerates from rest each time, which
/// stutters). A new tilt starts from where the tilt is now.
Future<void> easeTiltTo(GoogleMapController controller, double tilt) async {
  final view = mapViewOf(controller);
  final from = view.pose;
  if (from == null || view.touching) return;
  final easing = view._tiltEase;
  if (easing != null &&
      easing.generation == view.generation &&
      (easing.target - tilt).abs() < .5) {
    return easing.done.future;
  }
  view.interrupt();
  final generation = view.generation;
  CameraPosition at(CameraPosition base, double t) => CameraPosition(
    target: base.target,
    zoom: base.zoom,
    bearing: base.bearing,
    tilt: t,
  );
  final ease = view._tiltEase = (
    target: tilt,
    generation: generation,
    done: Completer<void>(),
  );
  view.easing = true;
  try {
    final started = DateTime.now();
    final fromTilt = from.tilt;
    for (var frames = 0; ; frames++) {
      final micros = math.max(
        DateTime.now().difference(started).inMicroseconds,
        frames * cameraEaseFrame.inMicroseconds,
      );
      final t = (micros / cameraTiltFlight.inMicroseconds).clamp(0.0, 1.0);
      final e = t * t * (3 - 2 * t);
      final base = view.pose ?? from;
      await _send(controller, view, at(base, fromTilt + (tilt - fromTilt) * e));
      if (view.generation != generation || t >= 1) break;
      await Future<void>.delayed(cameraEaseFrame);
      if (view.generation != generation) break;
    }
  } catch (_) {
    // The map went away mid-ease.
  } finally {
    if (view.generation == generation) view.easing = false;
    if (identical(view._tiltEase, ease)) view._tiltEase = null;
    ease.done.complete();
  }
}

/// Places [controller]'s camera at [to] immediately (no animation), and
/// stops any ease still running on it.
Future<void> placeCameraAt(GoogleMapController controller, CameraPosition to) {
  final view = mapViewOf(controller);
  if (view.touching) return Future<void>.value();
  view.interrupt();
  return _send(controller, view, to);
}

/// Runs a camera command the app cannot express as a pose (a plain bounds
/// fit), after stopping any ease still running on [controller].
Future<void> runCameraUpdate(
  GoogleMapController controller,
  CameraUpdate update,
) {
  final view = mapViewOf(controller);
  if (view.touching) return Future<void>.value();
  view.interrupt();
  return controller.animateCamera(update);
}
