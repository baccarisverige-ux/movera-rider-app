import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/location/geocoding_repository.dart';
import 'package:movera_rider/core/location/location_point.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/motion/location_smoother.dart';
import 'package:movera_rider/core/motion/motion_engine.dart';
import 'package:movera_rider/features/home/application/home_controller.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';

/// Batch 9 Phase 98 — U2 current-location reliability, D-002, D-003, D-004.
Position _position({
  double latitude = 59.33,
  double longitude = 18.06,
  double accuracy = 5,
  DateTime? at,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: at ?? DateTime.utc(2026, 9, 24),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 5,
  speed: 1,
  speedAccuracy: 1,
);

class _Location extends LocationRepository {
  StreamController<Position> stream = StreamController<Position>.broadcast();
  int subscriptions = 0;
  Completer<Position>? hang;
  Position current = _position(latitude: 59.5, longitude: 18.5);
  int currentRequests = 0;
  bool failDetection = false;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    currentRequests += 1;
    if (failDetection) return Future.error(StateError('no fix'));
    final pending = hang;
    if (pending != null) return pending.future;
    return Future.value(current);
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    subscriptions += 1;
    return stream.stream;
  }
}

class _Geocoding extends GeocodingRepository {
  @override
  Future<PlaceResult?> forward(String query) async => null;

  @override
  Future<String?> reverse(GeoPoint point) async => null;
}

HomeLocationController _controller(_Location location) =>
    HomeLocationController(
      location: location,
      geocoding: _Geocoding(),
      motion: MotionEngine(),
      startCompass: () async => false,
      readCompass: () => null,
      stopCompass: () {},
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('U2: a transient stream error re-subscribes with backoff', (
    tester,
  ) async {
    final location = _Location();
    final ctl = _controller(location);
    addTearDown(ctl.dispose);
    final fixes = <LatLng>[];
    ctl.startTracking(isMounted: () => true, onFix: (p, _) => fixes.add(p));
    expect(location.subscriptions, 1);

    location.stream.addError(StateError('temporary GPS loss'));
    await tester.pump();
    expect(ctl.state, HomeLocationState.temporarilyUnavailable);

    await tester.pump(HomeLocationController.resubscribeDelay(0));
    await tester.pump();
    expect(location.subscriptions, 2, reason: 'must not give up permanently');

    location.stream.add(_position(latitude: 59.41, longitude: 18.21));
    await tester.pump();
    expect(ctl.state, HomeLocationState.live);
    expect(fixes.last, const LatLng(59.41, 18.21));
  });

  testWidgets('U2: a permission error stops tracking without retrying', (
    tester,
  ) async {
    final location = _Location();
    final ctl = _controller(location);
    addTearDown(ctl.dispose);
    ctl.startTracking(isMounted: () => true, onFix: (_, __) {});
    location.stream.addError(const PermissionDeniedException('denied'));
    await tester.pump();
    expect(ctl.state, HomeLocationState.permissionRequired);
    await tester.pump(const Duration(seconds: 40));
    expect(location.subscriptions, 1);
  });

  test('U2: backoff grows and is capped', () {
    expect(HomeLocationController.resubscribeDelay(0).inSeconds, 2);
    expect(HomeLocationController.resubscribeDelay(1).inSeconds, 4);
    expect(HomeLocationController.resubscribeDelay(9).inSeconds, 30);
  });

  test('U2: a low-accuracy fix is shown once the good one is stale', () {
    final smoother = LocationSmoother();
    final t0 = DateTime.utc(2026, 9, 24, 12);
    LocationPoint point(double lat, int seconds, double accuracy) =>
        LocationPoint(
          point: GeoPoint(lat, 18.06),
          timestamp: t0.add(Duration(seconds: seconds)),
          accuracyMeters: accuracy,
          speedMps: 1,
        );

    // No good fix yet: a 300 m fix is better than nothing.
    expect(smoother.accept(point(59.30, 0, 300))?.point.latitude, 59.30);
    expect(smoother.accept(point(59.31, 1, 10))?.point.latitude, 59.31);
    // A fresh good fix still wins over a bad one.
    expect(smoother.accept(point(59.40, 3, 250))?.point.latitude, 59.31);
    // Once the good fix is stale the low-accuracy fix is shown.
    expect(smoother.accept(point(59.40, 15, 250))?.point.latitude, 59.40);
  });

  testWidgets('U2: un-pausing asks for a fresh fix', (tester) async {
    final location = _Location();
    final ctl = _controller(location);
    addTearDown(ctl.dispose);
    final fixes = <LatLng>[];
    ctl.startTracking(isMounted: () => true, onFix: (p, _) => fixes.add(p));
    ctl.pauseLiveUpdates();
    location.stream.add(_position(latitude: 59.2));
    await tester.pump();
    expect(fixes, isEmpty, reason: 'fixes are dropped while covered');

    ctl.resumeLiveUpdates();
    await tester.pump();
    expect(location.currentRequests, 1);
    expect(fixes.single, const LatLng(59.5, 18.5));
  });

  testWidgets('D-003: a hung getCurrentPosition times out on the Dart side', (
    tester,
  ) async {
    final location = _Location()..hang = Completer<Position>();
    final ctl = _controller(location);
    addTearDown(ctl.dispose);
    Object? error;
    unawaited(
      ctl.latestFix().catchError((Object e) {
        error = e;
        return null;
      }),
    );
    await tester.pump(HomeLocationController.latestFixTimeout);
    await tester.pump();
    expect(error, isA<TimeoutException>());

    final detected = ctl.detectCurrent();
    await tester.pump(HomeLocationController.detectFixTimeout);
    await tester.pump();
    final result = await detected;
    expect(result.target, isNull);
    expect(ctl.state, HomeLocationState.temporarilyUnavailable);
  });

  test('U2: a failed detection is never labelled "Current location"', () async {
    final location = _Location()..failDetection = true;
    final ctl = _controller(location);
    addTearDown(ctl.dispose);
    final detected = await ctl.detectCurrent();
    expect(detected.target, isNull);
    expect(detected.address, locationOffPickupLabel);
    expect(detected.address, isNot('Current location'));
  });

  test('rider-pin SPEC: the halo is a second screen-fixed marker under the '
      'pin; zoom, tilt and accuracy never change it ("Blue must be same in '
      'all zoom steps")', () async {
    final ctl = _controller(_Location());
    addTearDown(ctl.dispose);
    const at = LatLng(59.33, 18.06);
    final pinIcon = BitmapDescriptor.defaultMarker;
    final haloIcon = BitmapDescriptor.defaultMarkerWithHue(200);
    ctl.lastFixAccuracyMeters = 80;
    ctl.paintUserPuck(
      target: at,
      icon: pinIcon,
      heading: 0,
      haloIcon: haloIcon,
    );
    Marker byId(MarkerId id) => ctl.markers.firstWhere((m) => m.markerId == id);
    final halo = byId(HomeLocationController.userHaloId);
    final pin = byId(HomeLocationController.userPinId);
    expect(ctl.markers, hasLength(2));
    expect(identical(halo.icon, haloIcon), isTrue);
    expect(halo.position, at);
    expect(halo.anchor, const Offset(0.5, 0.5));
    expect(halo.flat, isFalse, reason: 'faces the screen: no tilt ellipse');
    expect(halo.consumeTapEvents, isTrue);
    expect(halo.zIndexInt, lessThan(pin.zIndexInt));
    expect(ctl.locationCircles, isEmpty, reason: 'no ground circle');
    final before = ctl.markers;
    var notified = 0;
    ctl.addListener(() => notified += 1);
    // Zoom and tilt steps leave the markers alone (no per-zoom repaint).
    for (final zoom in [12.0, 15.5, 19.0]) {
      ctl.lastMapZoom = zoom;
      ctl.noteCameraMove(tilt: zoom > 12 ? 45 : 0);
    }
    expect(identical(ctl.markers, before), isTrue);
    expect(notified, 0);
    // Another accuracy paints the same markers: nothing to repaint.
    ctl.lastFixAccuracyMeters = 900;
    ctl.paintUserPuck(
      target: at,
      icon: pinIcon,
      heading: 0,
      haloIcon: haloIcon,
    );
    expect(identical(ctl.markers, before), isTrue);
    expect(notified, 0);
  });

  test('rider-pin SPEC: the pin is a screen-facing marker anchored at its '
      'centre', () async {
    final ctl = _controller(_Location());
    addTearDown(ctl.dispose);
    ctl.paintUserPuck(
      target: const LatLng(59.33, 18.06),
      icon: BitmapDescriptor.defaultMarker,
      heading: 0,
    );
    final pin = ctl.markers.single;
    expect(pin.flat, isFalse);
    expect(pin.anchor, const Offset(0.5, 0.5));
  });

  test('D-004: coordinate strings and placeholders are recognised', () {
    expect(isRawCoordinateLabel('59.403200, 17.944700'), isTrue);
    expect(isRawCoordinateLabel('-33.8, 151.2'), isTrue);
    expect(isRawCoordinateLabel('Klockarvägen 37'), isFalse);
    expect(isPlaceholderPickupLabel('Current location'), isTrue);
    expect(isPlaceholderPickupLabel(locationOffPickupLabel), isTrue);
    expect(isPlaceholderPickupLabel('Sveavägen 1'), isFalse);
  });

  testWidgets('D-002: Confirm is disabled on a fallback pickup point', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ConfirmPickupSpot(
          initialPosition: LatLng(59.3293, 18.0686),
          initialAddress: locationOffPickupLabel,
          positionIsFallback: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm pickup'),
    );
    expect(confirm.onPressed, isNull);
    expect(find.byKey(const ValueKey('pickup-fallback-hint')), findsOneWidget);
    expect(find.text('Current location'), findsNothing);
  });
}
