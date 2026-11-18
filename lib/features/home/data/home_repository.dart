import 'dart:async';
import 'dart:convert';

import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/core/logging/app_log.dart';

class HomeAddressSnapshot {
  HomeAddressSnapshot({
    this.home,
    this.work,
    this.recent = const [],
    this.recentPoints = const {},
    this.places = const [],
    this.categories,
  });

  final String? home;
  final String? work;
  final List<String> recent;

  /// Owner 2026-11-17: the point of each recent that has one (for its km in
  /// Where to?). Recents saved before this have none.
  final Map<String, GeoPoint> recentPoints;
  final List<Map<String, String>> places;

  /// Saved-places design (owner 2026-11-18, contract v0.18.129): each
  /// place's fixed ride category, by [placeCategoryKey]. Null on a write =
  /// keep what the phone has (writers that do not know about categories).
  final Map<String, String>? categories;
}

const placeCategoriesKey = 'movera_place_categories_v1';

/// The key of a place's fixed category: `home`, `work`, or the address of a
/// custom place (its id changes when the server answers; the address not).
String placeCategoryKey(String kind, String address) => switch (kind) {
  'home' => 'home',
  'work' || 'office' => 'work',
  _ => 'addr:${address.trim().toLowerCase()}',
};

Map<String, String> decodePlaceCategories(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final e in decoded.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
  } catch (_) {
    return {};
  }
}

const recentPointsKey = 'movera_recent_points_v1';

Map<String, GeoPoint> decodeRecentPoints(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final points = <String, GeoPoint>{};
    decoded.forEach((key, value) {
      if (key is String &&
          value is List &&
          value.length == 2 &&
          value[0] is num &&
          value[1] is num) {
        points[key] = GeoPoint(
          (value[0] as num).toDouble(),
          (value[1] as num).toDouble(),
        );
      }
    });
    return points;
  } catch (_) {
    return {};
  }
}

String encodeRecentPoints(Map<String, GeoPoint> points) => jsonEncode({
  for (final e in points.entries) e.key: [e.value.latitude, e.value.longitude],
});

/// [places] with an id on every custom place, the same in Home and Saved
/// Places. A place stored before ids existed gets one from its position
/// (`place_legacy_<i>`).
///
/// rider-u220: a position-derived id could already be stored on another
/// place (after a delete the list shifts, and an older Home then appended
/// a place without an id), and an older Home wrote such a shared id back.
/// Deleting one of them removed both and editing one overwrote the other.
/// So the first place keeps a stored id, and a place without an id, or
/// with one an earlier place already has, gets an id no stored place uses.
List<Map<String, String>> withPlaceIds(List<Map<String, String>> places) {
  final taken = {
    for (final place in places)
      if ((place['id'] ?? '').trim().isNotEmpty) place['id']!.trim(),
  };
  final kept = <String>{};
  final result = <Map<String, String>>[];
  for (var i = 0; i < places.length; i++) {
    final id = (places[i]['id'] ?? '').trim();
    if (id.isNotEmpty && kept.add(id)) {
      result.add(places[i]);
      continue;
    }
    var fresh = 'place_legacy_$i';
    for (var n = 2; taken.contains(fresh); n++) {
      fresh = 'place_legacy_${i}_$n';
    }
    taken.add(fresh);
    kept.add(fresh);
    result.add({...places[i], 'id': fresh});
  }
  return result;
}

class HomeAddressRepository {
  static final StreamController<void> _changes =
      StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  Future<HomeAddressSnapshot> load() async {
    final prefs = await PreferencesStore.load();
    final places = <Map<String, String>>[];
    final raw = prefs.getString('movera_saved_places');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map) {
            final map = item.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            );
            if ((map['address'] ?? '').trim().isNotEmpty) places.add(map);
          }
        }
      } catch (error) {
        AppLog.warning(
          'home.saved_places_parse_failed',
          extra: {'error': '$error'},
        );
      }
    }
    return HomeAddressSnapshot(
      home: prefs.getString('movera_home_address'),
      work: prefs.getString('movera_work_address'),
      recent: prefs.getStringList('movera_recent_addresses') ?? <String>[],
      recentPoints: decodeRecentPoints(prefs.getString(recentPointsKey)),
      places: places,
      categories: decodePlaceCategories(prefs.getString(placeCategoriesKey)),
    );
  }

  Future<void> save(HomeAddressSnapshot data) async {
    try {
      final prefs = await PreferencesStore.load();
      if (data.home == null) {
        await prefs.remove('movera_home_address');
      } else {
        await prefs.setString('movera_home_address', data.home!);
      }
      if (data.work == null) {
        await prefs.remove('movera_work_address');
      } else {
        await prefs.setString('movera_work_address', data.work!);
      }
      await prefs.setStringList('movera_recent_addresses', data.recent);
      await prefs.setString(
        recentPointsKey,
        encodeRecentPoints({
          for (final address in data.recent)
            if (data.recentPoints[address] != null)
              address: data.recentPoints[address]!,
        }),
      );
      await prefs.setString('movera_saved_places', jsonEncode(data.places));
      if (data.categories != null) {
        await prefs.setString(placeCategoriesKey, jsonEncode(data.categories));
      }
    } catch (error) {
      // uat-r1: Home awaits this write right after a destination is
      // chosen. A refused write (iOS Safari: quota, Private Browsing on
      // older iOS, "Block All Cookies") threw out of that step and Select
      // Ride never opened. The addresses stay in memory for this session;
      // the device copy is best effort.
      AppLog.warning(
        'home.saved_places_write_refused',
        extra: {'error': error.toString()},
      );
      return;
    }
    _changes.add(null);
  }
}
