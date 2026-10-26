import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/features/pickup/data/previous_pickups_store.dart';
import 'package:movera_rider/features/pickup/domain/pickup_spot.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Metres between two points (equirectangular; fine for a few hundred m).
double pickupSpotDistanceM(LatLng a, LatLng b) {
  const metresPerDegree = 111320.0;
  final midLat = (a.latitude + b.latitude) / 2 * math.pi / 180;
  final dy = (b.latitude - a.latitude) * metresPerDegree;
  final dx = (b.longitude - a.longitude) * metresPerDegree * math.cos(midLat);
  return math.sqrt(dx * dx + dy * dy);
}

/// [point] moved [northM] metres north and [eastM] metres east.
LatLng pickupSpotOffset(LatLng point, {double northM = 0, double eastM = 0}) {
  const metresPerDegree = 111320.0;
  final lat = point.latitude + northM / metresPerDegree;
  final lng =
      point.longitude +
      eastM / (metresPerDegree * math.cos(point.latitude * math.pi / 180));
  return LatLng(lat, lng);
}

/// The street part of an address label: "Klockarvägen 37, Huddinge" →
/// "Klockarvägen 37". A label that already names a spot
/// ("Klockarvägen 37 – Main entrance") loses the spot too.
String pickupSpotStreet(String address) {
  var street = address.trim();
  final comma = street.indexOf(',');
  if (comma > 0) street = street.substring(0, comma);
  final dash = street.indexOf(' – ');
  if (dash > 0) street = street.substring(0, dash);
  return street.trim();
}

/// "Klockarvägen 37 – Main entrance": what the pickup card and the booking
/// show once a spot is chosen.
String pickupSpotLabel(String address, PickupSpot spot) {
  final street = pickupSpotStreet(address);
  return street.isEmpty ? spot.title : '$street – ${spot.title}';
}

/// Suggests pickup spots around an address and remembers confirmed pickups.
///
/// Mock for now: entrances and parking are placed deterministically around
/// the point; "Previously used" comes from the device's own confirmed
/// pickups; "Near Home" only when Home is within [nearHomeM].
class PickupSpotsController {
  PickupSpotsController({PreviousPickupsStore? store})
    : _store = store ?? SharedPreferencesPreviousPickupsStore();

  final PreviousPickupsStore _store;

  static const maxSpots = 6;
  static const maxPrevious = 2;
  static const keepPrevious = 5;
  static const nearHomeM = 300.0;

  /// Previously used spots farther than this from the point are not "here".
  static const previousRadiusM = 150.0;

  /// A previous pickup this close to the pin or to a named spot adds
  /// nothing: the pin or the named chip already covers it.
  static const sameSpotM = 12.0;

  Future<List<PickupSpot>> forAddress({
    required LatLng at,
    required String address,
    LatLng? home,
  }) async {
    // rider-55: titles and subtitles in the app language; a chosen spot's
    // title is also the booked pickup label's suffix.
    final l10n = L10n.current;
    final generated = <PickupSpot>[
      PickupSpot(
        id: 'entrance-main',
        title: l10n.pickupSpotMainEntrance,
        subtitle: l10n.pickupSpotFrontOfBuilding,
        kind: PickupSpotKind.entrance,
        position: pickupSpotOffset(at, northM: 25),
      ),
      PickupSpot(
        id: 'entrance-side',
        title: l10n.pickupSpotSideEntrance,
        subtitle: l10n.pickupSpotAroundCorner,
        kind: PickupSpotKind.entrance,
        position: pickupSpotOffset(at, northM: -30),
      ),
      PickupSpot(
        id: 'parking',
        title: l10n.pickupSpotParking,
        subtitle: l10n.pickupSpotShortWalk,
        kind: PickupSpotKind.parking,
        position: pickupSpotOffset(at, eastM: 60),
      ),
    ];
    if (home != null && pickupSpotDistanceM(at, home) <= nearHomeM) {
      generated.add(
        PickupSpot(
          id: 'home',
          title: l10n.pickupSpotNearHome,
          subtitle: l10n.pickupSpotMetresFromHere(
            pickupSpotDistanceM(at, home).round(),
          ),
          kind: PickupSpotKind.home,
          position: home,
        ),
      );
    }

    final previous = <PickupSpot>[];
    for (final p in await _previousNear(at)) {
      if (previous.length >= maxPrevious) break;
      final coversNamed = generated.any(
        (spot) => pickupSpotDistanceM(spot.position, p.position) <= sameSpotM,
      );
      if (coversNamed) continue;
      final spotName = _spotNameIn(p.address);
      previous.add(
        PickupSpot(
          id: 'previous-${previous.length}',
          title: l10n.pickupSpotPreviouslyUsed,
          subtitle: spotName ?? pickupSpotStreet(p.address),
          kind: PickupSpotKind.previous,
          position: p.position,
        ),
      );
    }

    return [...previous, ...generated].take(maxSpots).toList(growable: false);
  }

  /// Saves a confirmed pickup; the newest [keepPrevious] are kept.
  Future<void> remember({
    required LatLng position,
    required String address,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final existing = await _store.read();
    final kept = <PreviousPickup>[
      PreviousPickup(position: position, address: address.trim(), savedAt: now),
      for (final p in existing)
        if (pickupSpotDistanceM(p.position, position) > sameSpotM) p,
    ];
    kept.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    await _store.write(kept.take(keepPrevious).toList(growable: false));
  }

  Future<List<PreviousPickup>> _previousNear(LatLng at) async {
    final all = await _store.read();
    final near = all.where((p) {
      final d = pickupSpotDistanceM(at, p.position);
      return d > sameSpotM && d <= previousRadiusM;
    }).toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return near;
  }

  String? _spotNameIn(String address) {
    final dash = address.indexOf(' – ');
    if (dash < 0) return null;
    final name = address.substring(dash + 3).trim();
    return name.isEmpty ? null : name;
  }
}
