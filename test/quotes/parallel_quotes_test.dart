import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class _TrackingQuotes implements QuoteRepository {
  _TrackingQuotes({
    this.failRideId,
    this.delay = const Duration(milliseconds: 20),
  });

  final String? failRideId;
  final Duration delay;
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
      await Future<void>.delayed(delay);
      if (rideType == failRideId) throw StateError('quote failed');
      return RideQuote(
        id: 'q_$rideType',
        rideType: rideType,
        totalMinor: 25000,
        currency: 'SEK',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        signedPayload: 'test',
      );
    } finally {
      active -= 1;
    }
  }
}

void main() {
  test('quotes execute in bounded parallel batches', () async {
    final quotes = _TrackingQuotes();
    final selection = RideSelectionController(quotes: quotes);
    final generation = selection.beginQuotes();

    await selection.loadQuotes(
      generation: generation,
      pickup: 'A',
      destination: 'B',
      parallelism: 3,
    );

    expect(quotes.maxActive, 3);
    expect(selection.quoteIds.length, selection.rides().length);
  });

  test('one failed quote does not discard successful categories', () async {
    final quotes = _TrackingQuotes(failRideId: 'xl');
    final selection = RideSelectionController(quotes: quotes);
    final generation = selection.beginQuotes();

    await selection.loadQuotes(
      generation: generation,
      pickup: 'A',
      destination: 'B',
      parallelism: 3,
    );

    expect(selection.unavailableQuoteIds, contains('xl'));
    expect(selection.quoteIds['economy'], isNotNull);
    expect(selection.quoteIds['premium'], isNotNull);
  });

  test('per-quote timeout is isolated as unavailable', () async {
    final quotes = _TrackingQuotes(delay: const Duration(milliseconds: 40));
    final selection = RideSelectionController(quotes: quotes);
    final generation = selection.beginQuotes();

    await selection.loadQuotes(
      generation: generation,
      pickup: 'A',
      destination: 'B',
      timeout: const Duration(milliseconds: 5),
      parallelism: 2,
    );

    expect(selection.unavailableQuoteIds.length, selection.rides().length);
  });

  test('new quote generation prevents stale batch from writing', () async {
    final quotes = _TrackingQuotes(delay: const Duration(milliseconds: 25));
    final selection = RideSelectionController(quotes: quotes);
    final first = selection.beginQuotes();

    final stale = selection.loadQuotes(
      generation: first,
      pickup: 'A',
      destination: 'B',
      parallelism: 3,
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    selection.beginQuotes();
    await stale;

    expect(selection.quoteIds, isEmpty);
  });
}
