import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/features/home/application/home_controller.dart'
    show isPlaceholderPickupLabel, isRawCoordinateLabel;
import 'package:movera_rider/features/home/data/home_repository.dart';

class SavedPlaceData {
  const SavedPlaceData({
    required this.title,
    required this.type,
    required this.address,
    this.id,
  });

  final String title;
  final String type;
  final String address;

  /// Saved Places' identity for this place (FLOW-5); kept on every write.
  final String? id;

  Map<String, String> toJson() => {
    if (id != null) 'id': id!,
    'title': title,
    'type': type,
    'address': address,
  };

  factory SavedPlaceData.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'other';
    return SavedPlaceData(
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : type,
      type: type,
      address: json['address'] as String? ?? '',
      id: json['id'] as String?,
    );
  }
}

/// Owns saved/recent/home/work/pickup/destination/stops and trip pickup.
/// Home presentation only paints.
class HomePlacesController {
  HomePlacesController({HomeAddressRepository? store})
      : _store = store ?? HomeAddressRepository();

  final HomeAddressRepository _store;

  Stream<void> get changes => _store.changes;

  static const maxRecent = 8;
  static const maxCustom = 8;

  String? pickupAddress;
  String? destinationAddress;
  String? homeAddress;
  String? workAddress;
  List<String> routeStops = [];
  List<String> recentAddresses = [];
  List<SavedPlaceData> savedPlaces = [];

  /// rider-40: stored custom places past [maxCustom]. Home shows only the
  /// first [maxCustom], but Saved Places has no cap, so these are written
  /// back unchanged on every [persist] instead of being deleted.
  List<Map<String, String>> _placesBeyondCap = [];
  LatLng? currentLatLng;
  LatLng? tripPickupLatLng;

  Future<void> load() async {
    final saved = await _store.load();
    homeAddress = saved.home;
    workAddress = saved.work;
    recentAddresses = List<String>.from(saved.recent);
    // rider-41: a place stored before ids existed gets the id Saved Places
    // gives it, so it can be edited on its own (rider-u220: never an id
    // another place has).
    savedPlaces = [
      for (final place in withPlaceIds(saved.places).take(maxCustom))
        SavedPlaceData.fromJson(place),
    ];
    _placesBeyondCap = [
      for (final place in saved.places.skip(maxCustom))
        Map<String, String>.from(place),
    ];
  }

  Future<void> persist() {
    return _store.save(
      HomeAddressSnapshot(
        home: homeAddress,
        work: workAddress,
        recent: recentAddresses,
        places: [
          ...savedPlaces.map((place) => place.toJson()),
          ..._placesBeyondCap,
        ],
      ),
    );
  }

  /// rider-46: placeholders ('Location off, set pickup') and raw
  /// coordinates are not places; they never become Recents.
  void remember(String address) {
    final clean = address.trim();
    if (isPlaceholderPickupLabel(clean) || isRawCoordinateLabel(clean)) return;
    recentAddresses.removeWhere(
      (saved) => saved.toLowerCase() == clean.toLowerCase(),
    );
    recentAddresses.insert(0, clean);
    if (recentAddresses.length > maxRecent) {
      recentAddresses = recentAddresses.take(maxRecent).toList();
    }
  }

  String? existingFor(String target) {
    switch (target) {
      case 'pickup':
        return pickupAddress;
      case 'home':
        return homeAddress;
      case 'work':
        return workAddress;
      case 'destination':
        return destinationAddress;
      default:
        return null;
    }
  }

  void applyResolved({
    required String target,
    required String address,
    LatLng? pickupPosition,
    String? customType,
    String? placeId,
  }) {
    // rider-46: a placeholder is never saved as a place.
    if (target != 'pickup' && isPlaceholderPickupLabel(address)) return;
    switch (target) {
      case 'pickup':
        pickupAddress = address;
        tripPickupLatLng = pickupPosition;
        break;
      case 'destination':
        destinationAddress = address;
        break;
      case 'home':
        homeAddress = address;
        break;
      case 'work':
        workAddress = address;
        break;
      case 'custom':
        final type = customType ?? 'other';
        // rider-41: an edit names its place by id. Several places can share
        // a kind (FLOW-5), so without an id this is a new place.
        final existingIndex = placeId == null
            ? -1
            : savedPlaces.indexWhere((place) => place.id == placeId);
        if (existingIndex >= 0) {
          // Same place, new address: keep its name and id (FLOW-5).
          final existing = savedPlaces[existingIndex];
          savedPlaces[existingIndex] = SavedPlaceData(
            id: existing.id,
            title: existing.title,
            type: existing.type,
            address: address,
          );
        } else if (savedPlaces.length < maxCustom) {
          savedPlaces.add(
            SavedPlaceData(
              id: 'place_${newRequestId()}',
              title: type,
              type: type,
              address: address,
            ),
          );
        }
        break;
    }
    remember(address);
  }
}
