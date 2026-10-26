import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/features/pickup/domain/pickup_spot.dart';

/// The last confirmed pickups on this device (SharedPreferences, newest
/// first). Storage failures read as "nothing saved": the spots are a
/// convenience, never a blocker.
class SharedPreferencesPreviousPickupsStore implements PreviousPickupsStore {
  static const key = 'movera_previous_pickups_v1';

  @override
  Future<List<PreviousPickup>> read() async {
    try {
      final prefs = await PreferencesStore.load();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <PreviousPickup>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final lat = item['lat'];
        final lng = item['lng'];
        final address = item['address'];
        final savedAt = DateTime.tryParse('${item['savedAt']}');
        if (lat is! num ||
            lng is! num ||
            address is! String ||
            savedAt == null) {
          continue;
        }
        result.add(
          PreviousPickup(
            position: LatLng(lat.toDouble(), lng.toDouble()),
            address: address,
            savedAt: savedAt,
          ),
        );
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> write(List<PreviousPickup> pickups) async {
    try {
      final prefs = await PreferencesStore.load();
      await prefs.setString(
        key,
        jsonEncode([
          for (final p in pickups)
            {
              'lat': p.position.latitude,
              'lng': p.position.longitude,
              'address': p.address,
              'savedAt': p.savedAt.toIso8601String(),
            },
        ]),
      );
    } catch (_) {
      // Nothing to do: the next confirm tries again.
    }
  }
}
