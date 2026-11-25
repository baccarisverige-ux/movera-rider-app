import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/active_ride/application/route_change_controller.dart';
import 'package:movera_rider/features/active_ride/presentation/route_change_flow.dart';
import 'package:movera_rider/features/destination_search/presentation/route_picker_page.dart';
import 'package:movera_rider/features/home/application/home_places_controller.dart';
import 'package:movera_rider/features/pickup/presentation/confirm_pickup_spot.dart';
import 'package:movera_rider/l10n/l10n.dart';
import 'package:movera_rider/shared/widgets/early_input_capture.dart';
import 'package:movera_rider/shared/widgets/navigation_transition.dart';

/// Owner 2026-11-23: where the rider is, for their marker on the searching
/// map. Never shares anything with the server (live sharing starts only
/// after a driver accepts).
class SearchingRiderLocation {
  const SearchingRiderLocation();

  static bool _granted(LocationPermission p) =>
      p == LocationPermission.whileInUse || p == LocationPermission.always;

  /// The rider's position without asking: null without permission, with
  /// Location Services off or without a fix.
  Future<GeoPoint?> current() async {
    try {
      final repo = AppScope.instance.location;
      if (!_granted(await repo.checkPermission())) return null;
      if (!await repo.isLocationServiceEnabled()) return null;
      final position = await repo.getCurrentPosition().timeout(
        const Duration(seconds: 10),
      );
      final point = GeoPoint(position.latitude, position.longitude);
      return point.isValid ? point : null;
    } catch (_) {
      return null;
    }
  }

  /// "Dela plats": asks for location permission (or opens the settings
  /// that fix it), then reads the position.
  Future<GeoPoint?> request() async {
    try {
      final repo = AppScope.instance.location;
      if (!await repo.isLocationServiceEnabled() && !repo.isWeb) {
        await Geolocator.openLocationSettings();
        return null;
      }
      var permission = await repo.checkPermission();
      if (!_granted(permission)) permission = await repo.requestPermission();
      if (permission == LocationPermission.deniedForever && !repo.isWeb) {
        await Geolocator.openAppSettings();
        return null;
      }
      return await current();
    } catch (_) {
      return null;
    }
  }
}

/// Owner 2026-11-23 ("Justera"): what the pickup edit mode needs, on the
/// app's existing services and the existing route change flow.
class SearchingPickupEditor {
  const SearchingPickupEditor();

  /// The address at [point] (the app's reverse geocoding).
  Future<String?> addressAt(GeoPoint point) async {
    try {
      return await AppScope.instance.geocoding.reverse(point);
    } catch (_) {
      return null;
    }
  }

  /// The new price of moving the pickup beyond the free zone.
  Future<RouteChangeQuote?> quote(
    RideSnapshot ride,
    String address,
    GeoPoint point,
  ) async {
    try {
      return await previewSearchingPickup(
        ride: ride,
        address: address,
        point: point,
      );
    } catch (_) {
      return null;
    }
  }

  /// Moves the pickup (existing flow: same-price move or the priced change).
  Future<RideSnapshot?> apply(
    BuildContext context,
    RideSnapshot ride,
    String address,
    GeoPoint point,
    RouteChangeQuote? quote,
  ) => applySearchingPickup(
    context,
    ride: ride,
    address: address,
    point: point,
    quote: quote,
  );

  /// The app's existing place search (the route picker on its pickup
  /// field). Returns the picked pickup, or null.
  Future<RoutePickerMapPick?> search(
    BuildContext context,
    RideSnapshot ride,
  ) async {
    final places = HomePlacesController();
    await places.load();
    if (!context.mounted) return null;
    final capture = EarlyInputCapture()..start();
    RoutePickerMapPick? picked;
    try {
      await Navigator.of(context).push<Map<String, dynamic>>(
        BottomToTopTransition(
          RoutePickerPage(
            pageTitle: context.l10n.liveAdjustPickupButton,
            pickupAddress: ride.pickupAddress,
            destinationAddress: ride.destinationAddress,
            destinationPoint: GeoPoint(
              ride.destinationLat,
              ride.destinationLng,
            ),
            stops: [for (final stop in ride.stops) stop.address],
            stopPoints: [
              for (final stop in ride.stops)
                GeoPoint(stop.latitude, stop.longitude),
            ],
            stopsSupported: true,
            pickupLocked: false,
            driverOnTheWay: false,
            initialField: 'pickup',
            finishLabel: context.l10n.done,
            capture: capture,
            here: GeoPoint(ride.pickupLat, ride.pickupLng),
            homeAddress: places.homeAddress,
            workAddress: places.workAddress,
            savedPlaces: places.savedPlaces,
            recent: places.recentAddresses,
            onPickOnMap: ({required pickup, required address}) async {
              final result = await ConfirmPickupSpot.open(
                context,
                initialPosition: LatLng(ride.pickupLat, ride.pickupLng),
                initialAddress: address.isEmpty ? ride.pickupAddress : address,
                title: context.l10n.confirmPickupSpot,
                confirmLabel: context.l10n.confirmPickup,
              );
              if (result == null) return null;
              return RoutePickerMapPick(
                address: result.address,
                point: GeoPoint(
                  result.position.latitude,
                  result.position.longitude,
                ),
              );
            },
            onFinish: (selection) async {
              final point = selection.pickupPoint;
              if (point != null) {
                picked = RoutePickerMapPick(
                  address: selection.pickup,
                  point: point,
                );
              }
              return <String, dynamic>{};
            },
          ),
        ),
      );
    } finally {
      capture.stop();
    }
    return picked;
  }
}
