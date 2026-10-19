import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/fare/domain/fare_rules.dart';
import 'package:movera_rider/features/finding_driver/presentation/price_bump_card.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/data/mock_quote_repository.dart';
import 'package:movera_rider/features/ride_booking/domain/entities/quote.dart';
import 'package:movera_rider/features/ride_selection/application/ride_selection_controller.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/features/ride_booking/domain/route_stop.dart';

class AlwaysFailQuotes implements QuoteRepository {
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
  }) {
    return Future<RideQuote>.error(StateError('quote unavailable'));
  }
}

void main() {
  test('FareRules exposes and enforces one authoritative ceiling', () {
    expect(FareRules.minimum(100), 65);
    expect(FareRules.maximum(100), 180);
    expect(FareRules.allowsTotal(total: 180, catalog: 100), isTrue);
    expect(FareRules.allowsTotal(total: 181, catalog: 100), isFalse);
  });

  testWidgets('typed delayed offer cannot exceed FareRules ceiling', (tester) async {
    int? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PriceBumpCard(
            currentPrice: 100,
            maxPrice: 180,
            steps: const <int>[50],
            onConfirm: (value) => confirmed = value,
            onKeepWaiting: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '181');
    await tester.pump();
    expect(find.text('Set new price'), findsOneWidget);
    await tester.tap(find.text('Set new price'));
    expect(confirmed, isNull);

    await tester.enterText(find.byType(TextField), '180');
    await tester.pump();
    await tester.tap(find.text('Confirm 180 kr'));
    expect(confirmed, 80);
  });

  test('API quote failure is surfaced instead of silently falling back', () async {
    final transport = InProcessMockClient()..failNext = true;
    final quotes = ApiQuoteRepository(
      api: ApiClient(client: transport),
    );

    await expectLater(
      quotes.quote(
        rideType: 'economy',
        distanceMeters: 3000,
        pickup: 'A',
        destination: 'B',
      ),
      throwsA(isA<ApiError>()),
    );
    expect(quotes.lastUsedFallback, isFalse);
  });

  test('selection marks failed quotes unavailable and not bookable', () async {
    final selection = RideSelectionController(quotes: AlwaysFailQuotes());
    final generation = selection.beginQuotes();

    await selection.loadQuotes(
      generation: generation,
      pickup: 'A',
      destination: 'B',
    );

    expect(selection.quoteIsAvailable('economy'), isFalse);
    expect(selection.quoteIdFor('economy'), isNull);
    expect(selection.unavailableQuoteIds, contains('economy'));
  });
}
