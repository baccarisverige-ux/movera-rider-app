import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/location/place_search.dart';
import 'package:movera_rider/features/destination_search/application/destination_search_controller.dart';

/// Phase 141: the destination_search feature directory had zero test
/// coverage. DestinationSearchController debounces typed input through
/// PlaceSearchService and only calls back for the latest keystroke.
void main() {
  test(
    'type() calls back with the typed text once the debounce settles',
    () async {
      final controller = DestinationSearchController(
        PlaceSearchService(delay: Duration.zero),
      );
      final results = <String>[];

      controller.type('Arlanda', results.add);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(results, ['Arlanda']);
    },
  );

  test(
    'a superseded keystroke never calls back, only the latest does',
    () async {
      final search = PlaceSearchService(delay: Duration.zero);
      final controller = DestinationSearchController(search);
      final results = <String>[];

      // Fire two keystrokes before either debounce settles - only the second
      // (current) generation should ever reach onReady.
      controller.type('Arla', results.add);
      controller.type('Arlanda', results.add);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(results, ['Arlanda']);
    },
  );
}
