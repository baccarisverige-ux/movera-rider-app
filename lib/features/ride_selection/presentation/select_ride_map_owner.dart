import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/maps/map_owners.dart';

/// Select ride may move the shared map camera only while no other screen
/// owns it. Confirm and search keeps Set pickup's map on top; a route fit
/// there moved its pin and re-geocoded the confirmed pickup.
bool selectRideMayMoveMap() {
  final owner = AppScope.instance.maps.activeOwner;
  return owner == null || owner == MapOwners.selectRide;
}
