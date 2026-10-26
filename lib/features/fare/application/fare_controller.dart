import 'package:movera_rider/features/fare/data/fare_repository.dart';

class FareController {
  FareController({FareRepository? fares}) : _fares = fares ?? FareRepository();
  final FareRepository _fares;

  double nudge({
    required double current,
    required double catalog,
    required int delta,
  }) {
    return _fares.nudge(current: current, catalog: catalog, delta: delta);
  }
}
