import 'package:flutter/material.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:movera_rider/features/saved_places/domain/saved_place.dart';
import 'package:movera_rider/shared/models/saved_places.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SavedPlacesController {
  SavedPlacesController({HomeAddressRepository? store})
    : _store = store ?? HomeAddressRepository();

  final HomeAddressRepository _store;
  final List<PlaceShortcut> _shortcuts = <PlaceShortcut>[];

  List<SavedPlacesModel> options() => [
    SavedPlacesModel(title: L10n.current.spAddHome, icon: Icons.house_rounded),
    SavedPlacesModel(
      title: L10n.current.spAddWork,
      icon: Icons.work_outline_rounded,
    ),
    SavedPlacesModel(
      title: L10n.current.spAddSchool,
      icon: Icons.bookmark_outline_rounded,
    ),
    SavedPlacesModel(
      title: L10n.current.spAddGym,
      icon: Icons.bookmark_outline_rounded,
    ),
  ];

  List<PlaceShortcut> shortcuts() =>
      List<PlaceShortcut>.unmodifiable(_shortcuts);

  Stream<void> get changes => _store.changes;

  /// Forgets the signed-out rider's places in memory.
  void clearLocal() => _shortcuts.clear();

  Future<void> hydrate() async {
    final snapshot = await _store.load();
    _shortcuts
      ..clear()
      ..addAll(_fromSnapshot(snapshot));
  }

  /// Saves [place] and returns it as stored.
  ///
  /// FLOW-5: Home and Work have one slot each, chosen by [PlaceShortcut.kind].
  /// Every other place is identified by its [PlaceShortcut.id]: a place
  /// without one is new and gets a generated id, so a second "Gym" is added
  /// next to the first instead of replacing it.
  Future<PlaceShortcut> save(PlaceShortcut place) async {
    final clean = PlaceShortcut(
      title: place.title.trim(),
      subtitle: place.subtitle.trim(),
      kind: _normalizeKind(place.kind),
      id: place.id?.trim().isNotEmpty == true ? place.id!.trim() : null,
    );
    if (clean.title.isEmpty || clean.subtitle.isEmpty) {
      throw ArgumentError('Saved place requires both a name and a location.');
    }

    final snapshot = await _store.load();
    final places = withPlaceIds(snapshot.places);

    String? home = snapshot.home;
    String? work = snapshot.work;
    var saved = clean;
    if (clean.kind == 'home') {
      home = clean.subtitle;
      saved = PlaceShortcut(
        title: L10n.current.placeHome,
        subtitle: clean.subtitle,
        kind: 'home',
      );
    } else if (clean.kind == 'office') {
      work = clean.subtitle;
      saved = PlaceShortcut(
        title: L10n.current.placeWork,
        subtitle: clean.subtitle,
        kind: 'office',
      );
    } else {
      final id = clean.id ?? 'place_${newRequestId()}';
      saved = PlaceShortcut(
        title: clean.title,
        subtitle: clean.subtitle,
        kind: clean.kind,
        id: id,
      );
      final index = places.indexWhere((item) => item['id'] == id);
      final encoded = <String, String>{
        'id': id,
        'title': clean.title,
        'type': clean.kind,
        'address': clean.subtitle,
      };
      if (index < 0) {
        places.add(encoded);
      } else {
        places[index] = encoded;
      }
    }

    await _store.save(
      HomeAddressSnapshot(
        home: home,
        work: work,
        recent: snapshot.recent,
        places: places,
      ),
    );
    await hydrate();
    return saved;
  }

  /// Removes exactly [place]: the Home or Work slot, or the one custom
  /// place with its id (FLOW-5; it used to remove every place of a kind).
  Future<void> remove(PlaceShortcut place) async {
    final kind = _normalizeKind(place.kind);
    final snapshot = await _store.load();
    final id = place.id;
    final places = withPlaceIds(
      snapshot.places,
    ).where((item) => id == null || item['id'] != id).toList();

    await _store.save(
      HomeAddressSnapshot(
        home: kind == 'home' && id == null ? null : snapshot.home,
        work: kind == 'office' && id == null ? null : snapshot.work,
        recent: snapshot.recent,
        places: places,
      ),
    );
    await hydrate();
  }

  List<PlaceShortcut> _fromSnapshot(HomeAddressSnapshot snapshot) {
    final result = <PlaceShortcut>[];
    final home = snapshot.home?.trim();
    if (home?.isNotEmpty == true) {
      result.add(
        PlaceShortcut(
          title: L10n.current.placeHome,
          subtitle: home!,
          kind: 'home',
        ),
      );
    }
    final work = snapshot.work?.trim();
    if (work?.isNotEmpty == true) {
      result.add(
        PlaceShortcut(
          title: L10n.current.placeWork,
          subtitle: work!,
          kind: 'office',
        ),
      );
    }
    final places = withPlaceIds(snapshot.places);
    for (final item in places) {
      final address = (item['address'] ?? '').trim();
      if (address.isEmpty) continue;
      final kind = _normalizeKind(item['type'] ?? 'other');
      var title = (item['title'] ?? '').trim();
      // rider-42: a place saved from Home stores its type key ("gym") as
      // its title; show the type's label instead.
      if (title == (item['type'] ?? '').trim()) title = '';
      result.add(
        PlaceShortcut(
          title: title.isEmpty ? _labelForKind(kind) : title,
          subtitle: address,
          kind: kind,
          id: item['id'],
        ),
      );
    }
    return result;
  }

  String _normalizeKind(String value) {
    final lower = value.trim().toLowerCase();
    if (lower == 'work') return 'office';
    if (lower.isEmpty) return 'other';
    return lower;
  }

  /// The kinds Home can add, as placeLabelFor (saved_places_row.dart)
  /// names them; application code does not import presentation.
  static Map<String, String> get _customLabels => {
    'gym': L10n.current.placeGym,
    'mall': L10n.current.placeMall,
    'school': L10n.current.placeSchool,
    'airport': L10n.current.placeAirport,
    'family': L10n.current.placeFamily,
    'restaurant': L10n.current.placeRestaurant,
    'other': L10n.current.placeOther,
  };

  String _labelForKind(String kind) {
    if (kind == 'office') return L10n.current.placeWork;
    if (kind == 'home') return L10n.current.placeHome;
    final custom = _customLabels[kind];
    if (custom != null) return custom;
    return kind
        .split('-')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}
