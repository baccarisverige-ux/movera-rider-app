import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/destination_search/application/compact_address.dart';

/// rider-r5-39: French prefix regions are dropped like suffix ones.
void main() {
  test('Gouvernorat de … is not the town', () {
    expect(
      compactAddress(
        'Avenue Habib Bourguiba, Tunis, Gouvernorat de Tunis, 1000, Tunisie',
      ),
      'Avenue Habib Bourguiba, Tunis',
    );
    expect(
      compactAddress('Rue Nationale, Lille, Département du Nord, France'),
      'Rue Nationale, Lille',
    );
  });
}
