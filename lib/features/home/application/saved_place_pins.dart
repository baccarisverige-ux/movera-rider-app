import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/shared/widgets/movera_map_markers.dart'
    show markerPixelRatio;
import 'package:movera_rider/shared/widgets/saved_place_pin_marker.dart';

/// One saved place as a pin on Home's map.
@immutable
class SavedPlacePinEntry {
  const SavedPlacePinEntry({
    required this.key,
    required this.kind,
    required this.title,
    required this.address,
    required this.target,
    this.customType,
  });

  /// `home`, `work`, or the custom place's id.
  final String key;

  /// What the place is (home, office, gym, ...): picks the pin picture.
  final String kind;

  /// The name under the pin.
  final String title;
  final String address;

  /// What Home's saved-place tap takes: `home`, `work` or `custom`.
  final String target;
  final String? customType;

  SavedPinStyle get style => savedPinStyleFor(kind);

  @override
  bool operator ==(Object other) =>
      other is SavedPlacePinEntry &&
      other.key == key &&
      other.kind == kind &&
      other.title == title &&
      other.address == address &&
      other.target == target &&
      other.customType == customType;

  @override
  int get hashCode =>
      Object.hash(key, kind, title, address, target, customType);
}

/// Draws one frame of a pin.
typedef SavedPinDrawer =
    Future<SavedPinVisual> Function(
      SavedPinStyle style,
      String label, {
      required double grow,
      required double labelOpacity,
    });

/// One animation step: the drop's size about its tip, its tilt about the
/// tip (degrees) and the name's opacity.
typedef SavedPinFrame = ({double grow, double rotation, double label});

class _Pin {
  _Pin(this.entry, this.position);
  SavedPlacePinEntry entry;
  LatLng position;
  SavedPinFrame frame = SavedPlacePins.restFrame;
  Map<(double, double), SavedPinVisual> visuals = {};
  Timer? timer;
  int run = 0;
}

/// The rider's saved places as pins on Home's map (BQ-V11; owner
/// 2026-10-31, Rules plan/rider-saved-pins/SPEC.md, conversation
/// session-2026-10-30c.md:66, :70, :83).
///
/// - A pin exists only for a place the rider saved (SPEC 1); the list comes
///   from the server-synced phone copy that Home and Saved places show
///   (`GET /rider/places`, SPEC 9).
/// - It sits on the saved address (SPEC 2). The server and the phone keep
///   the address text only (contract `phoneDataToServer.riderPlaces.place`:
///   lat/lng optional, the app never sent them), so the position is the
///   address forward-geocoded, the same lookup a tap on the place makes;
///   found positions are kept for the app session.
/// - Saving makes the pin grow up from its point, bounce, give one tiny
///   shake, then the name fades in (SPEC 3); an edit replays that at the new
///   spot (SPEC 4); a delete shrinks it back into the ground (SPEC 5); the
///   places already saved come one after another when Home opens, once
///   (SPEC 6). With reduced motion the pins just appear.
class SavedPlacePins extends ChangeNotifier {
  SavedPlacePins({
    required GeocodingRepository geocoding,
    SavedPinDrawer? draw,
    double pixelRatio = markerPixelRatio,
    this.frameInterval = const Duration(milliseconds: 45),
    this.stagger = const Duration(milliseconds: 140),
    bool Function()? reduceMotion,
  }) : _geocoding = geocoding,
       _reduceMotion = reduceMotion ?? (() => false),
       _draw =
           draw ??
           ((style, label, {required grow, required labelOpacity}) =>
               SavedPlacePinMarker.create(
                 style,
                 label,
                 grow: grow,
                 labelOpacity: labelOpacity,
                 pixelRatio: pixelRatio,
               ));

  final GeocodingRepository _geocoding;
  final SavedPinDrawer _draw;
  final bool Function() _reduceMotion;
  final Duration frameInterval;
  final Duration stagger;

  /// A tap on a pin: Home opens the car categories with that place as the
  /// destination (SPEC 8).
  void Function(SavedPlacePinEntry entry)? onTap;

  /// Over the halo (1), under the rider's own pin (20).
  static const int zIndex = 10;

  static const SavedPinFrame restFrame = (grow: 1, rotation: 0, label: 1);

  /// Grow from the ground, bounce, one tiny shake, then the name.
  static const List<SavedPinFrame> appearFrames = [
    (grow: 0.2, rotation: 0, label: 0),
    (grow: 0.55, rotation: 0, label: 0),
    (grow: 0.9, rotation: 0, label: 0),
    (grow: 1.12, rotation: 0, label: 0),
    (grow: 0.95, rotation: 0, label: 0),
    (grow: 1, rotation: 0, label: 0),
    (grow: 1, rotation: 5, label: 0),
    (grow: 1, rotation: -5, label: 0),
    (grow: 1, rotation: 3, label: 0),
    (grow: 1, rotation: -2, label: 0),
    (grow: 1, rotation: 0, label: 0.5),
    restFrame,
  ];

  /// Back into the ground (short).
  static const List<SavedPinFrame> vanishFrames = [
    (grow: 0.7, rotation: 0, label: 0),
    (grow: 0.35, rotation: 0, label: 0),
  ];

  /// Positions found for an address (this app session).
  static final Map<String, LatLng> _positions = {};

  @visibleForTesting
  static void debugClearPositions() => _positions.clear();

  final Map<String, _Pin> _pins = {};
  final Map<String, _Pin> _leaving = {};
  Set<Marker> _markers = const <Marker>{};
  bool _shown = false;
  bool _disposed = false;
  int _generation = 0;

  /// The pins as they are now (a new set on every change).
  Set<Marker> get markers => _markers;

  static MarkerId markerIdFor(String key) => MarkerId('saved_place_$key');

  /// Shows exactly [entries]: new places appear, moved ones move, removed
  /// ones go. Completes once every new pin started its animation.
  Future<void> show(List<SavedPlacePinEntry> entries) async {
    if (_disposed) return;
    final generation = ++_generation;
    final first = !_shown;
    _shown = true;
    final wanted = {for (final e in entries) e.key: e};

    for (final key in _pins.keys.toList()) {
      if (!wanted.containsKey(key)) _vanish(_pins.remove(key)!);
    }

    var order = 0;
    final starts = <Future<void>>[];
    for (final entry in wanted.values) {
      final pin = _pins[entry.key];
      if (pin != null && pin.entry.address == entry.address) {
        if (pin.entry != entry) {
          // Same spot, new name or kind: redraw at rest.
          pin
            ..entry = entry
            ..visuals = {};
          starts.add(_settle(pin));
        }
        continue;
      }
      final delay = first ? stagger * order++ : Duration.zero;
      starts.add(_place(entry, generation, delay));
    }
    await Future.wait(starts);
  }

  Future<void> _settle(_Pin pin) async {
    await _visual(pin, restFrame);
    if (_disposed) return;
    pin.frame = restFrame;
    _publish();
  }

  Future<void> _place(
    SavedPlacePinEntry entry,
    int generation,
    Duration delay,
  ) async {
    final position = await _locate(entry.address);
    if (_disposed || generation != _generation) return;
    final old = _pins.remove(entry.key);
    old?.timer?.cancel();
    if (position == null) {
      // No position for this address: no pin (never a guess).
      if (old != null) _publish();
      return;
    }
    final pin = _Pin(entry, position);
    final frames = _reduceMotion() ? const [restFrame] : appearFrames;
    for (final frame in frames) {
      await _visual(pin, frame);
    }
    if (_disposed || generation != _generation) return;
    _pins[entry.key] = pin;
    _leaving.remove(entry.key)?.timer?.cancel();
    _animate(pin, frames, delay: delay);
  }

  void _vanish(_Pin pin) {
    pin.timer?.cancel();
    if (_reduceMotion()) {
      _publish();
      return;
    }
    final key = pin.entry.key;
    _leaving[key] = pin;
    unawaited(() async {
      for (final frame in vanishFrames) {
        await _visual(pin, frame);
      }
      if (_disposed || _leaving[key] != pin) return;
      _animate(pin, vanishFrames, then: () => _leaving.remove(key));
    }());
  }

  void _animate(
    _Pin pin,
    List<SavedPinFrame> frames, {
    Duration delay = Duration.zero,
    VoidCallback? then,
  }) {
    pin.timer?.cancel();
    final run = ++pin.run;
    var index = 0;
    void step() {
      if (_disposed || pin.run != run) return;
      if (index >= frames.length) {
        then?.call();
        _publish();
        return;
      }
      pin.frame = frames[index++];
      _publish();
      pin.timer = Timer(frameInterval, step);
    }

    if (delay == Duration.zero) {
      step();
    } else {
      // Hidden until its turn.
      pin.frame = (grow: 0, rotation: 0, label: 0);
      pin.timer = Timer(delay, step);
    }
  }

  Future<LatLng?> _locate(String address) async {
    final clean = address.trim();
    if (clean.isEmpty) return null;
    final known = _positions[clean];
    if (known != null) return known;
    PlaceResult? result;
    try {
      result = await _geocoding.forward(clean);
    } catch (_) {
      return null;
    }
    final GeoPoint? point = result?.point;
    if (point == null || !point.isValid) return null;
    final position = LatLng(point.latitude, point.longitude);
    _positions[clean] = position;
    return position;
  }

  Future<SavedPinVisual> _visual(_Pin pin, SavedPinFrame frame) async {
    final key = (frame.grow, frame.label);
    final kept = pin.visuals[key];
    if (kept != null) return kept;
    final drawn = await _draw(
      pin.entry.style,
      pin.entry.title,
      grow: frame.grow,
      labelOpacity: frame.label,
    );
    pin.visuals[key] = drawn;
    return drawn;
  }

  Marker? _markerFor(_Pin pin) {
    if (pin.frame.grow <= 0) return null;
    final visual = pin.visuals[(pin.frame.grow, pin.frame.label)];
    if (visual == null) return null;
    final entry = pin.entry;
    return Marker(
      markerId: markerIdFor(entry.key),
      position: pin.position,
      icon: visual.icon,
      anchor: visual.anchor,
      rotation: pin.frame.rotation,
      zIndexInt: zIndex,
      // On phones a marker that lets the tap through makes Google move the
      // camera onto it.
      consumeTapEvents: true,
      onTap: () => onTap?.call(entry),
    );
  }

  void _publish() {
    if (_disposed) return;
    final shown = <Marker>{};
    for (final pin in [
      // A place saved again while it was still leaving shows once.
      for (final leaving in _leaving.values)
        if (!_pins.containsKey(leaving.entry.key)) leaving,
      ..._pins.values,
    ]) {
      final marker = _markerFor(pin);
      if (marker != null) shown.add(marker);
    }
    _markers = shown;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final pin in [..._pins.values, ..._leaving.values]) {
      pin.timer?.cancel();
    }
    _pins.clear();
    _leaving.clear();
    super.dispose();
  }
}
