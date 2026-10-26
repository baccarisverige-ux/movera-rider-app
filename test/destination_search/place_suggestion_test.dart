import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/location/place_search.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/destination_search/application/destination_search_controller.dart';

void main() {
  test('search ignores case and Swedish letters', () {
    expect(foldForSearch('Klockarvägen'), 'klockarvagen');
    expect(matchRange('Klockarvägen 110', 'klo'), (0, 3));
    expect(matchRange('Klockarvägen 110', 'arvag'), (5, 10));
    expect(matchRange('Klockarvägen 110', 'xyz'), isNull);
  });

  test('distance labels', () {
    expect(formatDistanceKm(0.4), '<1 km');
    expect(formatDistanceKm(1.0), '1 km');
    expect(formatDistanceKm(1.24), '1.2 km');
    expect(formatDistanceKm(38.4), '38 km');
    const s = PlaceSuggestion(
      title: 'Alby Centrum',
      point: GeoPoint(59.2393, 17.8457),
    );
    expect(s.distanceKm(null), isNull);
    expect(s.distanceKm(const GeoPoint(59.1955, 17.6253))!, closeTo(13.4, 1));
  });

  Future<List<PlaceSuggestion>> suggest(String query) async {
    final controller = DestinationSearchController(
      PlaceSearchService(),
      api: ApiClient(),
    );
    late List<PlaceSuggestion> out;
    await controller.suggest(query, onReady: (_, results) => out = results);
    return out;
  }

  test('suggestions understand partial and misspelled input', () async {
    expect(
      (await suggest('klockarvagen')).first.title,
      startsWith('Klockarvägen'),
    );
    final drottn = await suggest('drottn 5');
    expect(drottn.map((s) => s.title), contains('Drottninggatan 5'));
    final arlanda = await suggest('arlanda');
    expect(arlanda.first.title, 'Stockholm Arlanda Airport');
    expect(arlanda.first.point, isNotNull);
  });

  test('an older, slower answer never replaces the newest one', () async {
    final controller = DestinationSearchController(
      PlaceSearchService(),
      api: ApiClient(),
    );
    final seen = <String>[];
    final first = controller.suggest('kl', onReady: (q, _) => seen.add(q));
    final second = controller.suggest('klo', onReady: (q, _) => seen.add(q));
    await Future.wait([first, second]);
    expect(seen, ['klo']);
  });
}
