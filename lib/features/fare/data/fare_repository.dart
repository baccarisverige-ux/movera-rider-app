import 'package:movera_rider/features/fare/domain/fare_rules.dart';

class FareRepository {
  double nudge({
    required double current,
    required double catalog,
    required int delta,
  }) {
    return FareRules.nudge(current: current, catalog: catalog, delta: delta);
  }
}
