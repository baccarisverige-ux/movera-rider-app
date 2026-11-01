import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/l10n/l10n.dart';

/// Page audit 2026-11-01: addresses do not end with an English country.
void main() {
  test('the country at the end of an address is dropped', () {
    expect(
      L10n.withoutCountry('Sydgatan 1, 151 38 Södertälje, Sweden'),
      'Sydgatan 1, 151 38 Södertälje',
    );
    expect(
      L10n.withoutCountry('10 Rue de Rivoli, 75004 Paris, France'),
      '10 Rue de Rivoli, 75004 Paris',
    );
    expect(L10n.withoutCountry('Kungsgatan 1, Sverige'), 'Kungsgatan 1');
    // A place named only by the country, or with it inside, is kept.
    expect(L10n.withoutCountry('Sweden'), 'Sweden');
    expect(L10n.withoutCountry('Swedenborgsgatan 4'), 'Swedenborgsgatan 4');
  });
}
