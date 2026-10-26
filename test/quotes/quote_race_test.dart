import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/core/feature_flags/feature_flags.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/catalog_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/features/ride_selection/data/ride_selection_repository.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class _SlowThenFast implements QuoteRepository {
  _SlowThenFast(this.fast);
  final QuoteRepository fast;
  int calls = 0;

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
    final call = ++calls;
    final delay = call == 1 ? const Duration(milliseconds: 40) : Duration.zero;
    await Future<void>.delayed(delay);
    return RideQuote(
      id: 'q_$call',
      rideType: rideType,
      totalMinor: call == 1 ? 11100 : 25900,
      currency: 'SEK',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      signedPayload: 'mock-api',
    );
  }
}

void main() {
  test('quote id equals quoteId', () async {
    final client = InProcessMockClient();
    final api = ApiClient(client: client);
    final json = await api.post(
      '/api/v1/quotes',
      body: {'rideType': 'economy'},
    );
    expect(json['quote']['id'], json['quote']['quoteId']);
    expect(json['quote']['totalMinor'], 25900);
    expect(json['quote']['currency'], 'SEK');
  });

  test('later quote generation wins', () async {
    final quotes = _SlowThenFast(CatalogQuoteRepository());
    final selection = RideSelectionController(
      store: RideSelectionRepository(),
      quotes: quotes,
    );
    final first = selection.beginQuotes();
    final firstLoad = selection.loadQuotes(
      generation: first,
      pickup: 'A',
      destination: 'B',
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = selection.beginQuotes();
    final secondLoad = selection.loadQuotes(
      generation: second,
      pickup: 'A',
      destination: 'C',
    );
    await Future.wait([firstLoad, secondLoad]);
    expect(selection.offeredPrices['economy'], 259);
  });

  test('destination B remains authoritative when A finishes later', () async {
    final quotes = _SlowThenFast(CatalogQuoteRepository());
    final selection = RideSelectionController(
      store: RideSelectionRepository(),
      quotes: quotes,
    );
    final destA = selection.beginQuotes();
    final loadA = selection.loadQuotes(
      generation: destA,
      pickup: 'A',
      destination: 'Destination A',
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final destB = selection.beginQuotes();
    final loadB = selection.loadQuotes(
      generation: destB,
      pickup: 'A',
      destination: 'Destination B',
    );
    await Future.wait([loadA, loadB]);
    expect(selection.offeredPrices['economy'], 259);
  });

  test(
    'ride category change while quotes pending preserves selection',
    () async {
      final quotes = _SlowThenFast(CatalogQuoteRepository());
      final selection = RideSelectionController(
        store: RideSelectionRepository(),
        quotes: quotes,
      );
      final first = selection.beginQuotes();
      final load = selection.loadQuotes(
        generation: first,
        pickup: 'A',
        destination: 'B',
      );
      selection.selectRide('xl', 399);
      await load;
      expect(selection.selectedRideId, 'xl');
      expect(selection.quoteIds['economy'], startsWith('q_'));
    },
  );

  test('select ride and payment live on the controller', () {
    final selection = RideSelectionController(
      store: RideSelectionRepository(),
      quotes: CatalogQuoteRepository(),
      flags: const FeatureFlags(),
    );
    selection.selectRide('xl', 399);
    selection.selectPayment(0);
    selection.scheduleFor(DateTime(2026, 9, 13, 10));
    expect(selection.selectedRideId, 'xl');
    expect(selection.selectedPayment, 0);
    expect(selection.isScheduled, isTrue);
    expect(selection.quoteIdFor('missing'), isNull);
  });

  test('async quote return after widget-like dispose is dropped', () async {
    final quotes = _SlowThenFast(CatalogQuoteRepository());
    final selection = RideSelectionController(
      store: RideSelectionRepository(),
      quotes: quotes,
    );
    final first = selection.beginQuotes();
    final load = selection.loadQuotes(
      generation: first,
      pickup: 'A',
      destination: 'B',
    );
    selection.beginQuotes();
    await load;
    expect(selection.offeredPrices.containsKey('economy'), isFalse);
  });

  test('api quote repository parses mock contract', () async {
    final repo = ApiQuoteRepository(
      api: ApiClient(client: InProcessMockClient()),
    );
    final quote = await repo.quote(
      rideType: 'xl',
      distanceMeters: 3000,
      pickup: 'A',
      destination: 'B',
    );
    expect(quote.id.startsWith('q_xl_'), isTrue);
    expect(quote.signedPayload, 'mock-api');
  });
}
