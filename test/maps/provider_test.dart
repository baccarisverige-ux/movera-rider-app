import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/google_map_provider.dart';
import 'package:movera_rider/core/maps/map_facade.dart';
import 'package:movera_rider/core/maps/map_camera_controller.dart';
import 'package:movera_rider/core/maps/map_lifecycle.dart';
import 'package:movera_rider/core/maps/map_owners.dart';
import 'package:movera_rider/core/maps/marker_store.dart';

void main() {
  test('provider stores markers and routes', () {
    final maps = GoogleMapProvider();
    maps.upsertMarker('pickup', const GeoPoint(59.33, 18.06));
    maps.drawRoute('select', const [
      GeoPoint(59.33, 18.06),
      GeoPoint(59.34, 18.07),
    ]);
    expect(maps.markers['pickup']?.point.latitude, 59.33);
    expect(maps.routes['select']?.length, 2);
    maps.removeMarker('pickup');
    maps.clearRoute('select');
    expect(maps.markers['pickup'], isNull);
    expect(maps.routes['select'], isNull);
  });

  test('older owner cannot detach newer map', () {
    final maps = GoogleMapProvider();
    maps.debugAttach(MapOwners.home);
    maps.debugAttach(MapOwners.pickup);
    expect(maps.activeOwner, MapOwners.pickup);
    expect(maps.generation, 2);
    maps.detach(owner: MapOwners.home);
    expect(maps.activeOwner, MapOwners.pickup);
    maps.detach(owner: MapOwners.pickup);
    expect(maps.activeOwner, isNull);
    maps.detach(owner: MapOwners.home);
    expect(maps.activeOwner, isNull);
  });

  test('rapid push pop keeps a single active owner', () {
    final maps = GoogleMapProvider();
    maps.debugAttach(MapOwners.home);
    maps.debugAttach(MapOwners.pickup);
    maps.debugAttach(MapOwners.selectRide);
    maps.debugAttach(MapOwners.finding);
    maps.debugAttach(MapOwners.waiting);
    expect(maps.ownerStack, [
      MapOwners.home,
      MapOwners.pickup,
      MapOwners.selectRide,
      MapOwners.finding,
      MapOwners.waiting,
    ]);
    maps.detach(owner: MapOwners.waiting);
    maps.detach(owner: MapOwners.finding);
    expect(maps.activeOwner, MapOwners.selectRide);
    maps.detach(owner: MapOwners.home);
    expect(maps.activeOwner, MapOwners.selectRide);
  });

  test('recreated screen with same owner id moves to top', () {
    final maps = GoogleMapProvider();
    maps.debugAttach(MapOwners.home);
    maps.debugAttach(MapOwners.pickup);
    maps.debugAttach(MapOwners.home);
    expect(maps.activeOwner, MapOwners.home);
    expect(maps.ownerStack, [MapOwners.pickup, MapOwners.home]);
  });

  test('resume while nested ride screen is active does not detach it', () {
    final maps = GoogleMapProvider();
    maps.debugAttach(MapOwners.home);
    maps.debugAttach(MapOwners.waiting);
    maps.detach(owner: MapOwners.home);
    expect(maps.activeOwner, MapOwners.waiting);
    expect(maps.generation, 2);
  });

  test('camera calls are no-ops without a live controller', () async {
    final maps = GoogleMapProvider();
    await maps.animateCamera(const GeoPoint(59.3, 18.0));
    await maps.moveCamera(const GeoPoint(59.3, 18.0));
    await maps.fitBounds(
      const GeoPoint(59.3, 18.0),
      const GeoPoint(59.4, 18.1),
    );
    expect(maps.controller, isNull);
  });

  test('re-attach moves owner to top and bumps generation', () {
    final maps = GoogleMapProvider();
    maps.debugAttach(MapOwners.home);
    maps.debugAttach(MapOwners.selectRide);
    maps.debugAttach(MapOwners.home);
    expect(maps.activeOwner, MapOwners.home);
    expect(maps.generation, 3);
    maps.detach(owner: MapOwners.selectRide);
    expect(maps.activeOwner, MapOwners.home);
    maps.detach(owner: MapOwners.home);
    expect(maps.activeOwner, isNull);
  });

  test('dispose drops owners and never needs a plugin controller', () {
    final maps = GoogleMapProvider();
    maps.debugAttach(MapOwners.finding);
    maps.debugAttach(MapOwners.waiting);
    maps.dispose();
    expect(maps.activeOwner, isNull);
    expect(maps.controller, isNull);
  });

  test('detached background owners never resurrect after active map leaves', () {
    final maps = GoogleMapProvider();
    final ownerChanges = <String?>[];
    maps.onOwnerDebug = (owner, _) => ownerChanges.add(owner);

    maps.debugAttach(MapOwners.home);
    maps.debugAttach(MapOwners.finding);
    maps.debugAttach(MapOwners.waiting);
    expect(maps.activeOwner, MapOwners.waiting);

    // Home/Finding can dispose after Waiting has already become current. Their
    // controllers are gone at that point and must be removed from ownership,
    // not left underneath Waiting to become active again later.
    maps.detach(owner: MapOwners.home);
    maps.detach(owner: MapOwners.finding);
    expect(maps.activeOwner, MapOwners.waiting);

    maps.detach(owner: MapOwners.waiting);

    expect(maps.activeOwner, isNull);
    expect(maps.ownerStack, isEmpty);
    expect(
      ownerChanges.where((owner) => owner == null).length,
      1,
      reason: 'the final live controller must be released exactly once',
    );
  });

  test(
    'older nested screen disposing later cannot steal the current owner',
    () {
      final maps = GoogleMapProvider();
      maps.debugAttach(MapOwners.home);
      maps.debugAttach(MapOwners.pickup);
      maps.debugAttach(MapOwners.selectRide);
      maps.debugAttach(MapOwners.finding);
      maps.debugAttach(MapOwners.waiting);
      final generation = maps.generation;
      maps.detach(owner: MapOwners.home);
      maps.detach(owner: MapOwners.pickup);
      maps.detach(owner: MapOwners.selectRide);
      maps.detach(owner: MapOwners.finding);
      expect(maps.activeOwner, MapOwners.waiting);
      expect(maps.generation, generation);
      maps.detach(owner: MapOwners.waiting);
      expect(maps.activeOwner, isNull);
    },
  );

  test('ride-stage handoffs never expose overlapping map owners', () {
    final maps = GoogleMapProvider();

    void attachOnly(String owner) {
      maps.debugAttach(owner);
      expect(maps.ownerStack, [owner]);
      expect(maps.activeOwner, owner);
    }

    void release(String owner) {
      maps.detach(owner: owner);
      expect(maps.ownerStack, isEmpty);
      expect(maps.activeOwner, isNull);
    }

    attachOnly(MapOwners.home);
    release(MapOwners.home);

    attachOnly(MapOwners.finding);
    release(MapOwners.finding);

    attachOnly(MapOwners.waiting);
    release(MapOwners.waiting);

    // Driver-cancel recovery remounts the already-existing Finding surface.
    attachOnly(MapOwners.finding);
    release(MapOwners.finding);

    // Returning from the full ride stack lets Home create one fresh map owner.
    attachOnly(MapOwners.home);
  });

  test('facade coordinates marker and route state', () {
    final maps = GoogleMapProvider();
    final facade = MapFacade(
      provider: maps,
      camera: MapCameraController(maps),
      markers: MarkerStore(),
      lifecycle: MapLifecycleController(),
    );
    facade.upsertMarker('user', const GeoPoint(59.3, 18.0), heading: 45);
    facade.drawRoute(
      'select',
      const GeoPoint(59.3, 18.0),
      const GeoPoint(59.4, 18.1),
    );
    expect(facade.markers['user']?.heading, 45);
    expect(facade.route('select').length, 2);
  });
}
