import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:movera_rider/core/maps/map_camera_motion.dart';
import 'package:movera_rider/core/web/rider_map_bridge.dart';
import 'package:movera_rider/shared/widgets/custom_google_map.dart';

import '../fixtures/fake_maps_platform.dart';

/// On the web every Google map Flutter removes lives on in the plugin's
/// platform view registry (google.maps.Map has no destroy()). The widget
/// therefore asks the web layer to release the map when it is disposed; the
/// layer gives back its tiles, listeners and WebGL context once the element
/// is out of the DOM (web/rider_map_camera.js, measured in
/// docs/web-lifecycle-investigation.md).
void main() {
  late FakeMapsPlatform platform;
  late GoogleMapsFlutterPlatform previous;
  final released = <int>[];

  setUp(() {
    previous = GoogleMapsFlutterPlatform.instance;
    platform = FakeMapsPlatform();
    GoogleMapsFlutterPlatform.instance = platform;
    released.clear();
    RiderMapBridge.debugRelease = released.add;
    CustomGoogleMap.debugWaitForMaps = false;
  });

  tearDown(() {
    RiderMapBridge.debugRelease = null;
    CustomGoogleMap.debugWaitForMaps = null;
    GoogleMapsFlutterPlatform.instance = previous;
  });

  testWidgets('a disposed map is released to the web layer by its map id', (
    tester,
  ) async {
    GoogleMapController? created;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomGoogleMap(
            key: const ValueKey('probe-map'),
            onMapCreated: (controller) => created = controller,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(created, isNotNull, reason: 'the fake platform creates the view');
    expect(released, isEmpty, reason: 'nothing is released while mounted');

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(released, [created!.mapId]);
    expect(platform.disposed, [
      created!.mapId,
    ], reason: 'the plugin still disposes its own controller');
  });

  // Owner N5 (live test 2026-10-26): the green/red/yellow roads were
  // Google's live traffic layer. The shared map widget never turns it on;
  // the cloud Map ID is the only styling.
  testWidgets('the map never turns on Google\'s traffic layer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
    );
    await tester.pump();
    expect(platform.lastConfiguration?.trafficEnabled, isFalse);
  });

  testWidgets('a map disposed before it was created releases nothing', (
    tester,
  ) async {
    // The platform never answers: no controller, no map id to release.
    GoogleMapsFlutterPlatform.instance = FakeMapsPlatform(createsView: false);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomGoogleMap())),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(released, isEmpty);
  });

  testWidgets('every mount is recorded for the lifecycle tests', (
    tester,
  ) async {
    CustomGoogleMap.debugMounted.clear();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CustomGoogleMap(key: ValueKey('first'))),
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CustomGoogleMap(key: ValueKey('second'))),
      ),
    );
    expect(CustomGoogleMap.debugMounted, const [
      ValueKey('first'),
      ValueKey('second'),
    ]);
    CustomGoogleMap.debugMounted.clear();
  });

  // Owner N6 (pinch on the booking and trip maps: the camera snaps back or
  // flies in from far away). google_maps_flutter_web reports zoom 0 and a
  // (0, 0) centre when Maps has no value yet; such a report must not become
  // the camera's pose (the origin of the next ease) nor reach the screen.
  testWidgets('a web camera report without a zoom or a centre is dropped', (
    tester,
  ) async {
    GoogleMapController? created;
    final reported = <CameraPosition>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomGoogleMap(
            onMapCreated: (controller) => created = controller,
            onCameraMove: reported.add,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final id = created!.mapId;
    const frame = CameraPosition(target: LatLng(59.19, 17.62), zoom: 15.5);
    platform.emit(CameraMoveEvent(id, frame));
    await tester.pump();
    expect(mapViewOf(created!).pose, frame);

    platform
      ..emit(
        CameraMoveEvent(
          id,
          const CameraPosition(target: LatLng(59.19, 17.62), zoom: 0),
        ),
      )
      ..emit(
        CameraMoveEvent(
          id,
          const CameraPosition(target: LatLng(0, 0), zoom: 15),
        ),
      );
    await tester.pump();
    expect(mapViewOf(created!).pose, frame, reason: 'the gaps are no pose');
    expect(reported, [frame], reason: 'the screen sees frames only');
  });
}
