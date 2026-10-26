import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/in_process_mock_client.dart';
import 'package:movera_rider/features/ride_booking/data/api_quote_repository.dart';

void main() {
  ApiQuoteRepository repo([InProcessMockClient? client]) {
    return ApiQuoteRepository(
      api: ApiClient(client: client ?? InProcessMockClient()),
    );
  }

  test('successful quote matches catalog kr', () async {
    final quote = await repo().quote(rideType: 'economy', distanceMeters: 3000);
    expect(quote.totalMinor, 25900);
    expect(quote.currency, 'SEK');
    expect(quote.signedPayload, 'mock-api');
    expect(quote.expired, isFalse);
  });

  test('every ride category', () async {
    for (final type in <String>[
      'economy',
      'comfort',
      'premium',
      'priority',
      'xl',
      'electric',
      'pet',
    ]) {
      final quote = await repo().quote(rideType: type, distanceMeters: 1000);
      expect(quote.totalMinor, greaterThan(0));
      expect(quote.signedPayload, 'mock-api');
    }
  });

  test('timeout is surfaced instead of using a fallback fare', () async {
    final client = InProcessMockClient();
    client.timeoutNext = const Duration(milliseconds: 1);
    final quotes = repo(client);
    await expectLater(
      quotes.quote(rideType: 'comfort', distanceMeters: 1),
      throwsA(isA<ApiError>()),
    );
    expect(quotes.lastUsedFallback, isFalse);
  });

  test('HTTP 500 is surfaced instead of using a fallback fare', () async {
    final client = InProcessMockClient()..failNext = true;
    final quotes = repo(client);
    await expectLater(
      quotes.quote(rideType: 'premium', distanceMeters: 1),
      throwsA(isA<ApiError>()),
    );
    expect(quotes.lastUsedFallback, isFalse);
  });

  test('POST is not retried as GET would be', () async {
    final client = InProcessMockClient();
    final api = ApiClient(client: client);
    final first = await api.post('/api/v1/quotes', body: {'rideType': 'xl'});
    expect(first['quote']['totalMinor'], 39900);
  });

  test('timeout error type', () async {
    final client = InProcessMockClient()
      ..timeoutNext = const Duration(milliseconds: 1);
    expect(
      () => ApiClient(client: client).post('/api/v1/quotes', body: {}),
      throwsA(isA<ApiError>()),
    );
  });
}
