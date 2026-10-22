import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/domain/place_suggestion.dart';

/// rider-u82: the lookup itself failed (offline, timeout, server error),
/// which is not the same as "no address found".
class PlaceSuggestionsUnavailable implements Exception {
  const PlaceSuggestionsUnavailable(this.cause);
  final Object cause;

  @override
  String toString() => 'PlaceSuggestionsUnavailable($cause)';
}

/// Address suggestions from `/api/v1/locations/autocomplete`.
class PlaceSuggestionRepository {
  PlaceSuggestionRepository(this._api);

  final ApiClient? _api;

  /// Throws [PlaceSuggestionsUnavailable] when the request fails; an empty
  /// list means the server found nothing.
  Future<List<PlaceSuggestion>> suggest(String query, {GeoPoint? near}) async {
    final api = _api;
    if (api == null || query.trim().isEmpty) return const [];
    try {
      final body = await api.post(
        '/api/v1/locations/autocomplete',
        body: {
          'query': query.trim(),
          if (near != null) 'latitude': near.latitude,
          if (near != null) 'longitude': near.longitude,
          'limit': 8,
        },
      );
      final list = body['suggestions'];
      if (list is! List) return const [];
      return list
          .map(PlaceSuggestion.fromJson)
          .whereType<PlaceSuggestion>()
          .toList();
    } catch (error) {
      throw PlaceSuggestionsUnavailable(error);
    }
  }
}
