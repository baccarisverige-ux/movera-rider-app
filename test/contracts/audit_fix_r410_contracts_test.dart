import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/contracts/matched_driver.dart';

/// Wave 4 R4.10: what the rider sends and reads on the contract wire.
void main() {
  group('rider-16 contract DriverSummary', () {
    const elin = MatchedDriver(
      id: 'drv_204',
      firstName: 'Elin',
      rating: 4.9,
      vehicleMake: 'Volvo',
      vehicleModel: 'XC40',
      vehicleColor: 'White',
      plate: 'MVR 204',
    );

    test('a DriverSummary with driverId and a nested vehicle parses', () {
      final driver = MatchedDriver.fromJson({
        'driverId': 'drv_204',
        'firstName': 'Elin',
        'rating': 4.9,
        'vehicle': {
          'make': 'Volvo',
          'model': 'XC40',
          'color': 'White',
          'plate': 'MVR 204',
        },
      });
      expect(driver?.id, 'drv_204');
      expect(driver?.plate, 'MVR 204');
      expect(driver?.vehicleLabel, 'White Volvo XC40');
    });

    test('toJson writes the contract shape; legacy flat keys still parse', () {
      final json = elin.toJson();
      expect(json['driverId'], 'drv_204');
      expect(json['vehicle'], {
        'make': 'Volvo',
        'model': 'XC40',
        'color': 'White',
        'plate': 'MVR 204',
      });
      expect(MatchedDriver.fromJson(json)?.vehicleLabel, 'White Volvo XC40');
      final legacy = MatchedDriver.fromJson(
        {'id': 'd1', 'firstName': 'Ana', 'plate': 'ABC 123'},
      );
      expect(legacy?.id, 'd1');
      expect(legacy?.plate, 'ABC 123');
    });
  });
}
