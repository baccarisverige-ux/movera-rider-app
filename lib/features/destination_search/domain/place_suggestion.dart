import 'dart:math' as math;

import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// One address or place offered while the rider types.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    this.subtitle = '',
    this.point,
    this.kind = PlaceSuggestionKind.address,
  });

  /// "Klockarvägen 110"
  final String title;

  /// "Södertälje" / "151 59 Södertälje"
  final String subtitle;

  /// Known coordinates; null for a recent address that has none stored.
  final GeoPoint? point;
  final PlaceSuggestionKind kind;

  /// Full one-line address, as the booking stores it.
  String get address => subtitle.isEmpty ? title : '$title, $subtitle';

  static PlaceSuggestion? fromJson(Object? json) {
    if (json is! Map) return null;
    final title = json['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final lat = json['latitude'];
    final lng = json['longitude'];
    final subtitle = json['subtitle'];
    return PlaceSuggestion(
      title: title.trim(),
      subtitle: subtitle is String ? subtitle.trim() : '',
      point: lat is num && lng is num
          ? GeoPoint(lat.toDouble(), lng.toDouble())
          : null,
    );
  }

  /// Straight-line distance in km from [from], or null when unknown.
  double? distanceKm(GeoPoint? from) {
    final to = point;
    if (from == null || to == null) return null;
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(to.latitude - from.latitude);
    final dLng = rad(to.longitude - from.longitude);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(from.latitude)) *
            math.cos(rad(to.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

enum PlaceSuggestionKind { address, recent, home, work, myLocation }

/// "<1 km", "1 km", "1.2 km", "38 km"; "1,2 km" in French and Swedish
/// (rider-u83).
String formatDistanceKm(double km) {
  if (km < 1) return '<1 km';
  if (km < 10) {
    final rounded = (km * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.toInt()} km'
        : '${L10n.formatDecimal(rounded)} km';
  }
  return '${km.round()} km';
}

/// Folds case and Swedish/French letters so "klockarvagen" finds
/// "Klockarvägen".
String foldForSearch(String value) {
  const from = 'åäöéèêëàâüïîôç';
  const to = 'aaoeeeeaauiioc';
  final lower = value.toLowerCase();
  final out = StringBuffer();
  for (final char in lower.split('')) {
    final i = from.indexOf(char);
    out.write(i < 0 ? char : to[i]);
  }
  return out.toString();
}

/// Where [query] matches inside [text] (folded), for highlighting the typed
/// letters, or null when it does not.
(int, int)? matchRange(String text, String query) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return null;
  final i = foldForSearch(text).indexOf(q);
  if (i < 0) return null;
  return (i, i + q.length);
}
