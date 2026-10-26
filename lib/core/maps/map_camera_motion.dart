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

  /// Clock for [followHold] and the glide's frame times (tests replace it).
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
    if (_jsMotion) {
      _jsMotion = false;
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

  /// True while the web layer moves the camera (a flight or a follow
  /// glide) on the browser's frame clock (requestAnimationFrame) instead of
  /// the Dart loop.
  bool _jsMotion = false;

  /// The Dart-stepped follow glide's speed in screen pixels per second; a
  /// newer goal keeps it, so a retarget never restarts from rest.
  double _glideSpeed = 0;

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

/// How long a follow glide takes for a typical gap (about 300 px on
/// screen). It is the glide's span, not a fixed clock: the glide closes
/// its gap at a speed proportional to what is left ([_glideTau] of the
/// span), accelerating from rest, and lands exactly on its goal. A newer
/// goal retargets it at the speed it has, never from rest.
const Duration cameraEaseDuration = Duration(milliseconds: 450);

/// The longest a flight (a recenter, a route fit) takes, start to rest.
/// Its real length scales with how far it goes ([flightDurationFor]):
/// short hops 250-350 ms, a typical recenter or fit 500-600 ms, this at
/// most. Unlike the follow glide, a flight runs on the clock: it eases in
/// and out ([flightEase]) and lands on its goal on time.
const Duration cameraFlightDuration = Duration(milliseconds: 700);

/// The shortest flight (a hop of a few pixels).
const Duration _shortestFlight = Duration(milliseconds: 250);

/// Glides asked for at least this long are flights ([cameraFlightDuration]);
/// shorter ones are the follow glide.
const Duration _flightThreshold = Duration(milliseconds: 600);

/// How long after a web flight lands its late camera echoes are ignored.
const Duration cameraEchoGrace = Duration(milliseconds: 600);

/// Interval between the poses of a stepped ease (about 60 fps).
const Duration cameraEaseFrame = Duration(milliseconds: 16);

/// The tilt that follows the rider's own zoom eases in this long.
const Duration cameraTiltFlight = Duration(milliseconds: 350);

/// A command that waits longer than this lands on its goal.
const int _maxEaseFrames = 240;

/// Screen pixels a zoom of one level, or a turn of one radian, moves the
/// map's edge by (a phone screen's corner is ~300 px from its centre).
/// Keep in step with web/rider_map_camera.js (PX_PER_LEVEL).
const double _pxPerLevel = 300;

/// A camera within this many screen pixels of its goal is there.
const double _settlePx = 1;

/// The follow glide's time constant as a share of its span (~120 ms at
/// [cameraEaseDuration]); one value for position, zoom and heading, so
/// none of them trails behind the others.
const double _glideTau = .27;

/// The glide closes its gap as if the goal were this many pixels further
/// on, so it reaches the goal in finite time (at about 1 px per frame)
/// instead of creeping towards it.
const double _glideLandingPx = 6;

/// How fast the follow glide may gain speed (px/s²): it leaves gently even
/// when the gap is big, and keeps its speed when retargeted.
const double _glideAccel = 40000;

/// The world's width in pixels at [zoom].
double _worldPx(double zoom) => 256 * math.pow(2, zoom).toDouble();

/// How far [a] and [b] are apart on screen, in pixels at [zoom]: the
/// largest of the pan, the zoom, the turn and the tilt (each as the pixels
/// it moves the map's edge by).
double _screenGap(CameraPosition a, CameraPosition b, double zoom) {
  final world = _worldPx(zoom);
  final lat = (a.target.latitude + b.target.latitude) / 2 * math.pi / 180;
  // Web Mercator: a degree of latitude is 1 / cos(lat) times taller than a
  // degree of longitude is wide.
  final dx = (b.target.longitude - a.target.longitude) / 360 * world;
  final dy =
      (b.target.latitude - a.target.latitude) /
      360 *
      world /
      math.max(.01, math.cos(lat));
  final pan = math.sqrt(dx * dx + dy * dy);
  final zoomPx = (b.zoom - a.zoom).abs() * _pxPerLevel;
  final turn = _angleDelta(a.bearing, b.bearing).abs() * math.pi / 180;
  final tilt = (b.tilt - a.tilt).abs() * math.pi / 180;
  return math.max(math.max(pan, zoomPx), math.max(turn, tilt) * _pxPerLevel);
}

/// Whether [a] and [b] look the same on screen (within [_settlePx]).
bool _settled(CameraPosition a, CameraPosition b) =>
    _screenGap(a, b, math.max(a.zoom, b.zoom)) <= _settlePx;

double _angleDelta(double from, double to) => (to - from + 540) % 360 - 180;

/// How long a flight from [from] to [to] takes: on a log scale of the pan
/// (in pixels at the wider of the two zooms) plus the zoom change, between
/// 250 ms for a hop and [cameraFlightDuration]. A 100 px pan takes about
/// 310 ms; a recenter from 11.7 to street zoom 15, or a 1000 px fit, about
/// 500-580 ms. The web layer is handed the length, so it needs no copy.
Duration flightDurationFor(CameraPosition from, CameraPosition to) {
  final pan = _screenGap(
    CameraPosition(target: from.target),
    CameraPosition(target: to.target),
    math.min(from.zoom, to.zoom),
  );
  final turn = _angleDelta(from.bearing, to.bearing).abs() / 90;
  final effort =
      math.log(1 + pan / 100) / math.ln2 +
      .6 * (to.zoom - from.zoom).abs() +
      .5 * turn;
  final ms = (220 + 90 * effort).clamp(
    _shortestFlight.inMilliseconds.toDouble(),
    cameraFlightDuration.inMilliseconds.toDouble(),
  );
  return Duration(milliseconds: ms.round());
}

/// One frame ([dtMicros]) of the follow glide from [from] to [to] at
/// [speed] (px/s): the speed goes towards the gap left (plus
/// [_glideLandingPx]) over the time constant, gaining at most
/// [_glideAccel], and the frame closes that many pixels of the gap.
/// Position, zoom, heading and tilt close the same share, so they arrive
/// together; the pan keeps an even speed on screen while the zoom changes
/// ([_panShare]) and the tilt rides the zoom as in [_blend]. Returns the
/// next pose (the goal itself once it is reached) and the new speed.
(CameraPosition, double) _glideStep(
  MapView view,
  CameraPosition from,
  CameraPosition to,
  int dtMicros,
  Duration duration,
  double speed,
) {
  final gap = _screenGap(from, to, math.max(from.zoom, to.zoom));
  if (gap <= _settlePx) return (to, 0);
  final tau = math.max(200000, duration.inMicroseconds) * _glideTau / 1e6;
  final dt = dtMicros / 1e6;
  final next = math.min(
    (gap + _glideLandingPx) / tau,
    speed + _glideAccel * dt,
  );
  final step = next * dt;
  if (step >= gap - _settlePx) return (to, next);
  final share = step / gap;
  return (
    _blend(
      view,
      from,
      to,
      share,
      panShare: _panShare(share, to.zoom - from.zoom),
    ),
    next,
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
  return (slowPhaseSpeed * x + (1 - slowPhaseSpeed) * _bumpIntegral(x)) / total;
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

/// [share] (0..1) of the way from [from] to [to]. The tilt rides the zoom
/// on the [view]'s curve, so it is the zoom's tilt on every frame; a tilt
/// off the curve (a hand tilt) is carried along and closes like the zoom.
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
  final tilt =
      (view.tiltFor(nextZoom) + fromOffset + (toOffset - fromOffset) * k).clamp(
        0.0,
        maxTiltForZoom(nextZoom),
      );
  return CameraPosition(
    target: LatLng(
      from.target.latitude + (to.target.latitude - from.target.latitude) * p,
      from.target.longitude + (to.target.longitude - from.target.longitude) * p,
    ),
    zoom: nextZoom,
    bearing:
        (from.bearing + _angleDelta(from.bearing, to.bearing) * k + 360) % 360,
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

/// Moves [controller]'s camera to [to] continuously, on phones and on the
/// web alike, like the driver app. A [duration] of at least 600 ms (a
/// recenter, [cameraFlightDuration]) is a flight that lands on time, as
/// long as its distance needs ([flightDurationFor]) and never longer than
/// [duration]; a shorter one is the follow glide ([cameraEaseDuration]),
/// which settles well under a second. A goal the camera already shows
/// (within a pixel) moves nothing.
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
  // below, so it gets its own clock instead of the follow glide's speed.
  final startsFlight = view._flight == null && duration >= _flightThreshold;
  if (view.easing && view._goal != null && running != null && !startsFlight) {
    view._goal = to;
    view._goalDuration = duration;
    final id = view.mapId;
    if (view._jsMotion && id != null) {
      RiderMapBridge.retarget(id, to);
      return running.future;
    }
    // A newer goal joins a running flight on its clock (a fresh fix after a
    // recenter, a follow update), so the flight still lands on time; a
    // follow glide turns to it at the speed it has.
    return running.future;
  }
  final current = view.pose;
  // Nothing to do: the camera already shows the goal.
  if (!view.easing && current != null && _settled(current, to)) {
    return Future<void>.value();
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
  view._flight = duration >= _flightThreshold
      ? Duration(
          microseconds: math.min(
            duration.inMicroseconds,
            flightDurationFor(from, to).inMicroseconds,
          ),
        )
      : null;
  view._flownMicros = 0;
  view._glideSpeed = 0;
  view.easing = true;
  // On the web flights and follow glides run in the gesture layer on the
  // browser's frame clock: one camera move per painted frame, so they never
  // stutter on a Dart timer (Safari). Other platforms step here.
  final id = view.mapId;
  final flight = view._flight;
  final js = id == null
      ? null
      : flight != null
      ? RiderMapBridge.flight(id, to, flight)
      : RiderMapBridge.glide(id, to, duration);
  if (js != null) {
    view._jsMotion = true;
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
      view._jsMotion = false;
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
        final (pose, speed) = _glideStep(
          view,
          from,
          goal,
          // A stalled frame (a busy tab) does not leap.
          math.min(dt, cameraEaseFrame.inMicroseconds * 4),
          view._goalDuration,
          view._glideSpeed,
        );
        view._glideSpeed = speed;
        last = frame >= _maxEaseFrames || identical(pose, goal);
        next = last ? goal : pose;
      }
      await _send(controller, view, next);
      if (last || view.generation != generation) return;
      final started = MapView.now();
      await Future<void>.delayed(cameraEaseFrame);
      // Real time, but never less than one frame, so a glide also ends
      // where the clock barely moves (tests, fast frames).
      dt = math.max(
        cameraEaseFrame.inMicroseconds,
        MapView.now().difference(started).inMicroseconds,
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
