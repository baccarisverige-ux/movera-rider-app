import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/maps/marker_store.dart';
import 'package:movera_rider/core/performance/performance_budgets.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class _BudgetQuotes implements QuoteRepository {
  int active = 0;
  int maxActive = 0;

  @override
  Future<RideQuote> quote({
    required String rideType,
    required int distanceMeters,
    int durationSeconds = 600,
    String? pickup,
    String? destination,
    GeoPoint? pickupPoint,
    GeoPoint? destinationPoint,
    List<RouteStop> stops = const <RouteStop>[],
  }) async {
    active += 1;
    if (active > maxActive) maxActive = active;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return RideQuote(
        id: 'q_$rideType',
        rideType: rideType,
        totalMinor: 25000,
        currency: 'SEK',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        signedPayload: 'budget-test',
      );
    } finally {
      active -= 1;
    }
  }
}

void main() {
  test('certified performance budgets stay explicit', () {
    expect(PerformanceBudgets.quoteParallelism, 3);
    expect(PerformanceBudgets.quoteConcurrencyCeiling, 3);
    expect(PerformanceBudgets.quoteTimeout, const Duration(seconds: 8));
    expect(PerformanceBudgets.markerMinimumMoveMeters, 1.5);
    expect(PerformanceBudgets.markerMinimumHeadingDegrees, 3);
  });

  test(
    'default quote loading respects certified concurrency ceiling',
    () async {
      final quotes = _BudgetQuotes();
      final selection = RideSelectionController(quotes: quotes);
      final generation = selection.beginQuotes();

      await selection.loadQuotes(
        generation: generation,
        pickup: 'A',
        destination: 'B',
      );

      expect(
        quotes.maxActive,
        lessThanOrEqualTo(PerformanceBudgets.quoteConcurrencyCeiling),
      );
      expect(quotes.maxActive, greaterThan(1));
      selection.dispose();
    },
  );

  test('default marker budget suppresses sensor-scale jitter', () {
    final store = MarkerStore();
    const start = GeoPoint(59.329300, 18.068600);
    const jitter = GeoPoint(59.329301, 18.068601);

    final first = store.upsert('rider', start, heading: 10);
    final second = store.upsert('rider', jitter, heading: 11);

    expect(identical(first, second), isTrue);
  });
}
