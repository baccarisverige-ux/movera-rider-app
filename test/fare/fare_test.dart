import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/motion/bearing.dart';
import 'package:movera_rider/core/security/anti_abuse.dart';
import 'package:movera_rider/features/fare/domain/fare_breakdown.dart';
import 'package:movera_rider/shared/formatters/money.dart';

void main() {
  test('fare formula', () {
    const fare = FareBreakdown(
      baseMinor: 8900,
      distanceMinor: 1200,
      timeMinor: 400,
      bookingFeeMinor: 500,
      surgeMinor: 200,
      promotionMinor: 1000,
    );
    expect(fare.finalMinor, 8900 + 1200 + 400 + 500 + 200 - 1000);
    expect(formatSek(fare.finalMinor), '102 kr');
  });

  test('heading wrap cases', () {
    expect(shortestTurn(0, 10), 10);
    expect(shortestTurn(350, 10), 20);
    expect(shortestTurn(10, 350), -20);
    expect(shortestTurn(359, 1), closeTo(2, 0.001));
  });

  test('impossible travel', () {
    expect(
      AntiAbuse.impossibleTravel(
        meters: 10000,
        window: const Duration(seconds: 1),
      ),
      isTrue,
    );
  });
}
