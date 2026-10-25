import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';

/// Owner round 1: right after sign-in Home shows a fast position first
/// (the OS's cached fix, else a quick coarse one), binds the accurate fix
/// before its address is known, and the push primer waits for the location
/// answer.
Position _position(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.utc(2026, 10, 25),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _Location extends LocationRepository {
  LocationPermission permission = LocationPermission.whileInUse;
  Completer<LocationPermission>? prompt;
  GeoPoint? cached;
  Position? coarse;
  bool approximate = false;
  final Completer<Position> accurate = Completer<Position>();
  final List<LocationAccuracy?> asked = [];

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() =>
      prompt?.future ?? Future.value(permission);

  @override
  Future<GeoPoint?> lastKnownFix() async => cached;

  @override
  Future<bool> isApproximateOnly() async => approximate;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    asked.add(locationSettings?.accuracy);
    if (locationSettings?.accuracy == LocationAccuracy.low) {
      final fix = coarse;
      return fix == null
          ? Completer<Position>().future
          : Future<Position>.value(fix);
    }
    return accurate.future;
  }

  @override
  Future<void> saveLastGoodFix(GeoPoint point) async {}

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream.empty();
}

class _Geocoding extends GeocodingRepository {
  final Completer<String?> answer = Completer<String?>();

  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) => answer.future;
}

HomeLocationController _controller(_Location location, _Geocoding geo) =>
    HomeLocationController(
      location: location,
      geocoding: geo,
      motion: MotionEngine(),
      startCompass: () async => false,
      readCompass: () => null,
      stopCompass: () {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(LocationPromptGate.reset);

  test('the OS cached fix is shown before the accurate fix lands', () async {
    final location = _Location()..cached = const GeoPoint(59.30, 18.00);
    final geo = _Geocoding()..answer.complete('Drottninggatan 1');
    final controller = _controller(location, geo);
    addTearDown(controller.dispose);
    final quick = <LatLng>[];

    final detecting = controller.detectCurrent(onQuickFix: quick.add);
    await pumpEventQueue();
    expect(quick, [const LatLng(59.30, 18.00)]);
    expect(location.asked, [
      LocationAccuracy.high,
    ], reason: 'a cached fix needs no extra request');

    location.accurate.complete(_position(59.3326, 18.0649));
    final detected = await detecting;
    expect(detected.target, const LatLng(59.3326, 18.0649));
    expect(detected.address, 'Drottninggatan 1');
    expect(quick, hasLength(1));
  });

  test('without a cached fix a quick low-accuracy fix is asked for', () async {
    final location = _Location()..coarse = _position(59.31, 18.01);
    final geo = _Geocoding()..answer.complete(null);
    final controller = _controller(location, geo);
    addTearDown(controller.dispose);
    final quick = <LatLng>[];

    final detecting = controller.detectCurrent(onQuickFix: quick.add);
    await pumpEventQueue();
    expect(location.asked, [LocationAccuracy.high, LocationAccuracy.low]);
    expect(quick, [const LatLng(59.31, 18.01)]);
    location.accurate.complete(_position(59.3326, 18.0649));
    await detecting;
  });

  test('a quick fix that comes after the accurate one is dropped', () async {
    final location = _Location();
    final geo = _Geocoding()..answer.complete(null);
    final controller = _controller(location, geo);
    addTearDown(controller.dispose);
    final quick = <LatLng>[];
    location.accurate.complete(_position(59.3326, 18.0649));
    await controller.detectCurrent(onQuickFix: quick.add);
    // The coarse request never answers; nothing late arrives either.
    await pumpEventQueue();
    expect(quick, isEmpty);
  });

  test('the accurate point is handed over before the reverse geocode '
      'answers', () async {
    final location = _Location();
    final geo = _Geocoding();
    final controller = _controller(location, geo);
    addTearDown(controller.dispose);
    final located = <DetectedLocation>[];
    var done = false;

    unawaited(
      controller.detectCurrent(onLocated: located.add).then((_) => done = true),
    );
    location.accurate.complete(_position(59.3326, 18.0649));
    await pumpEventQueue();
    expect(located.single.target, const LatLng(59.3326, 18.0649));
    expect(located.single.address, 'Current location');
    expect(done, isFalse, reason: 'the address is still being looked up');

    geo.answer.complete('Drottninggatan 1');
    await pumpEventQueue();
    expect(done, isTrue);
  });

  test('approximate only: no pickup point is handed over', () async {
    final location = _Location()..approximate = true;
    final geo = _Geocoding();
    final controller = _controller(location, geo);
    addTearDown(controller.dispose);
    final located = <DetectedLocation>[];
    location.accurate.complete(_position(59.3326, 18.0649));
    final detected = await controller.detectCurrent(onLocated: located.add);
    expect(located, isEmpty);
    expect(detected.approximate, isTrue);
    expect(detected.address, locationOffPickupLabel);
  });

  test('the push primer waits for the location answer', () async {
    final location = _Location()
      ..permission = LocationPermission.denied
      ..prompt = Completer<LocationPermission>();
    final geo = _Geocoding()..answer.complete(null);
    final controller = _controller(location, geo);
    addTearDown(controller.dispose);

    LocationPromptGate.expect();
    var answered = false;
    unawaited(LocationPromptGate.answered().then((_) => answered = true));
    final detecting = controller.detectCurrent();
    await pumpEventQueue();
    expect(answered, isFalse, reason: 'the OS location prompt is still open');

    location.prompt!.complete(LocationPermission.denied);
    await detecting;
    await pumpEventQueue();
    expect(answered, isTrue);
  });

  test('nothing expected: the primer does not wait', () async {
    var answered = false;
    unawaited(LocationPromptGate.answered().then((_) => answered = true));
    await pumpEventQueue();
    expect(answered, isTrue);
  });
}
