import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:movera_rider/core/maps/geo_point.dart';
import 'package:movera_rider/core/location/web_reverse_geocode.dart';

void main() {
  test('street, number, area and city read like a Swedish address', () {
    expect(
      formatOpenStreetMapAddress({
        'road': 'Klockarvägen',
        'house_number': '37',
        'suburb': 'Geneta',
        'city': 'Södertälje',
        'country': 'Sverige',
      }),
      'Klockarvägen 37, Geneta, Södertälje',
    );
  });

  test('missing parts are skipped and a duplicated city is not repeated', () {
    expect(
      formatOpenStreetMapAddress({'road': 'Storgatan', 'town': 'Nyköping'}),
      'Storgatan, Nyköping',
    );
    expect(
      formatOpenStreetMapAddress({'suburb': 'Centrum', 'city': 'Centrum'}),
      'Centrum',
    );
    expect(formatOpenStreetMapAddress({'country': 'Sverige'}), isNull);
  });

  // rider-r4-44: French and Tunisian addresses put the number first, and the
  // request asks for the app's language, not the browser's.
  test('a French address reads number first', () {
    expect(
      formatOpenStreetMapAddress({
        'road': 'Rue de Rivoli',
        'house_number': '37',
        'city': 'Paris',
        'country_code': 'fr',
      }),
      '37 Rue de Rivoli, Paris',
    );
  });

  test('the lookup asks Nominatim for the app language', () async {
    Uri? asked;
    await openStreetMapReverse(
      const GeoPoint(48.86, 2.35),
      language: 'fr',
      client: MockClient((request) async {
        asked = request.url;
        return http.Response('{}', 200);
      }),
    );
    expect(asked?.queryParameters['accept-language'], 'fr');
  });
}
