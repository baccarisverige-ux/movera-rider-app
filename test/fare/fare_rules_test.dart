import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/fare/domain/fare_rules.dart';

void main() {
  test('nudge stays inside 65%–200% of catalog', () {
    expect(FareRules.nudge(current: 259, catalog: 259, delta: -200), 168);
    expect(FareRules.nudge(current: 259, catalog: 259, delta: 2000), 518);
    expect(FareRules.nudge(current: 259, catalog: 259, delta: 1), 260);
  });
}
