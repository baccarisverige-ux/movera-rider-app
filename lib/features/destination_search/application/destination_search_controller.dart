import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/location/place_search.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/data/destination_search_repository.dart';
import 'package:movera_rider/features/destination_search/data/place_suggestion_repository.dart';
import 'package:movera_rider/features/destination_search/domain/place_suggestion.dart';

export 'package:movera_rider/features/destination_search/domain/place_suggestion.dart';

class DestinationSearchController {
  DestinationSearchController(this._search, {ApiClient? api})
    : _suggestions = PlaceSuggestionRepository(api);

  final PlaceSearchService _search;
  final PlaceSuggestionRepository _suggestions;
  final _store = DestinationSearchRepository();
  int _suggestGeneration = 0;

  /// How many suggestion requests went out (rider-u86 checks the debounce).
  @visibleForTesting
  int get suggestRequests => _suggestGeneration;

  void type(String value, void Function(String text) onReady) {
    _search.query(value, (text, generation) {
      if (!_search.isCurrent(generation)) return;
      _store.remember(text);
      onReady(text);
    });
  }

  /// Suggestions for [query]; [onReady] only fires for the latest query, so
  /// a slow answer for "Kl" never replaces the one for "Klo".
  ///
  /// rider-u82: when the lookup fails, [onFailed] fires instead (else
  /// [onReady] with no results), so the screen does not say the address
  /// does not exist when the lookup never ran.
  Future<void> suggest(
    String query, {
    GeoPoint? near,
    required void Function(String query, List<PlaceSuggestion> results) onReady,
    void Function(String query)? onFailed,
  }) async {
    final generation = ++_suggestGeneration;
    List<PlaceSuggestion> results;
    try {
      results = await _suggestions.suggest(query, near: near);
    } on PlaceSuggestionsUnavailable {
      if (generation != _suggestGeneration) return;
      if (onFailed != null) {
        onFailed(query);
      } else {
        onReady(query, const []);
      }
      return;
    }
    if (generation != _suggestGeneration) return;
    _store.remember(query);
    onReady(query, results);
  }
}
