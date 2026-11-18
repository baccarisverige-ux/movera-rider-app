import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/features/home/data/home_repository.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Saved-places design (owner 2026-11-18, Rules
/// decisions/session-2026-11-18-saved-places-design.md steps 3b-7): saves
/// a recent address as a place from the categories screen's save sheet, its
/// undo, and the place's fixed ride category. Every write goes through the
/// phone copy ([HomeAddressRepository]); the server sync sends it on
/// (`ServerSavedPlaces`, the existing saved-places API).
class PlaceQuickSave {
  PlaceQuickSave({HomeAddressRepository? store, bool Function()? supported})
    : _store = store ?? HomeAddressRepository(),
      _supported = supported ?? _serverSupports;

  final HomeAddressRepository _store;
  final bool Function() _supported;

  /// The save sheet's types, in the approved order (S3).
  static const types = ['home', 'work', 'school', 'gym', 'family', 'other'];

  static bool _serverSupports() {
    try {
      return AppScope.instance.savedPlacesServer?.supportsPreferredCategory ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Whether a fixed category can be stored: only on a v0.18.129 server
  /// (an older one never answers the field; the question is skipped).
  bool get categorySupported => _supported();

  /// The localized name of [type].
  static String label(String type) => switch (type) {
    'home' => L10n.current.placeHome,
    'work' => L10n.current.placeWork,
    'school' => L10n.current.placeSchool,
    'gym' => L10n.current.placeGym,
    'family' => L10n.current.placeFamily,
    _ => L10n.current.placeOther,
  };

  /// Saves [address] as [type]; answers the phone copy from before, for
  /// [undo]. Home and Work replace the slot's address.
  Future<HomeAddressSnapshot> save(String address, String type) async {
    final before = await _store.load();
    final clean = address.trim();
    final places = [...before.places];
    String? home = before.home;
    String? work = before.work;
    if (type == 'home') {
      home = clean;
    } else if (type == 'work') {
      work = clean;
    } else {
      places.add({
        'id': 'place_${DateTime.now().microsecondsSinceEpoch}',
        'title': label(type),
        'type': type,
        'address': clean,
      });
    }
    await _store.save(
      HomeAddressSnapshot(
        home: home,
        work: work,
        recent: before.recent,
        recentPoints: before.recentPoints,
        places: withPlaceIds(places),
      ),
    );
    return before;
  }

  /// "Ångra": puts the phone copy back as it was before [save].
  Future<void> undo(HomeAddressSnapshot before) async {
    final now = await _store.load();
    await _store.save(
      HomeAddressSnapshot(
        home: before.home,
        work: before.work,
        recent: now.recent,
        recentPoints: now.recentPoints,
        places: before.places,
        categories: before.categories,
      ),
    );
  }

  /// Fixes [categoryId] for the place [address] saved as [type].
  Future<void> fixCategory(
    String address,
    String type,
    String categoryId,
  ) async {
    final now = await _store.load();
    await _store.save(
      HomeAddressSnapshot(
        home: now.home,
        work: now.work,
        recent: now.recent,
        recentPoints: now.recentPoints,
        places: now.places,
        categories: {
          ...?now.categories,
          placeCategoryKey(type, address): categoryId,
        },
      ),
    );
  }

  /// The fixed category of the place [address] of kind [kind], if any.
  Future<String?> categoryFor(String kind, String address) async {
    final now = await _store.load();
    return now.categories?[placeCategoryKey(kind, address)];
  }
}
