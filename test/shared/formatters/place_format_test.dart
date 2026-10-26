import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/shared/formatters/place_format.dart';

/// Phase 132 clusters 2 + 6: select_ride.dart's _compactAddress and
/// finding_drivers.dart's _shortPlace were byte-identical already (split on
/// ',', drop postcode-like tokens matching ^\d{3,}$, join the first two
/// parts) and now both delegate to [shortenPlace] unchanged for every
/// input verified below.
///
/// [shortenPlace] intentionally uses the more comprehensive numeric-suffix
/// regex from waiting_sheet_bits.dart's shortPickupPlace (^\d{3,}(\s?\d{2})?$,
/// cluster 6's "most correct" pattern) instead of the plainer ^\d{3,}$ the
/// other two used, so it also strips a space-formatted Swedish postcode
/// ("123 45") as a standalone part — a real input the old regex missed.
/// That one input is called out below as an intentional difference, not a
/// parity failure.
///
/// reservation_format.dart's old shortPlace was the least correct of the
/// four: it never filtered postcode-like tokens at all, and returned the
/// raw untrimmed-internally string whenever 2 or fewer comma groups
/// survived — so it could keep a postcode that displaced the real place
/// name (see the dedicated test below). Consolidating onto shortenPlace
/// fixes that; the reservation_format.dart caller has no test pinning its
/// old output (verified: `grep -r shortPlace test/` finds nothing), and its
/// only lib/ caller (ride_scheduled.dart) is not covered by an existing
/// widget test that would pin the old text.
void main() {
  String oldCompactAddressOrShortPlace(String value) {
    final parts = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .where((part) => !RegExp(r'^\d{3,}$').hasMatch(part))
        .toList();
    if (parts.isEmpty) return value;
    if (parts.length == 1) return parts.first;
    return '${parts[0]}, ${parts[1]}';
  }

  group(
    'parity with select_ride._compactAddress / finding_drivers._shortPlace',
    () {
      for (final input in [
        'Klockarvägen 37, Stockholm',
        'Arlanda Express',
        'Main St, 12345, Stockholm',
        'A, B, C, D',
        '  Spacey Street  ,  Uppsala  ',
        'Main St , Stockholm',
      ]) {
        test('matches old formula for "$input"', () {
          expect(shortenPlace(input), oldCompactAddressOrShortPlace(input));
        });
      }
    },
  );

  test('Phase 132 cluster 6 improvement: a space-formatted Swedish postcode '
      '("123 45") is now stripped, unlike the plainer regex the old '
      '_compactAddress/_shortPlace used', () {
    const input = 'Main St, 123 45, Stockholm';
    expect(
      oldCompactAddressOrShortPlace(input),
      'Main St, 123 45',
      reason: 'old regex only matched all-digit tokens, missing this one',
    );
    expect(shortenPlace(input), 'Main St, Stockholm');
  });

  test('Phase 132 fix: unlike the old buggy reservation_format.shortPlace, a '
      'postcode is stripped instead of displacing the real place name', () {
    const input = 'Main St, 12345, Stockholm';
    // Old shortPlace never filtered numerics: 3 raw comma groups, not
    // <=2, so it joined the first two unfiltered groups verbatim.
    String oldReservationFormatShortPlace(String raw) {
      final clean = raw.trim();
      if (clean.isEmpty) return clean;
      final parts = clean
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.length <= 2) return clean;
      return '${parts[0]}, ${parts[1]}';
    }

    expect(
      oldReservationFormatShortPlace(input),
      'Main St, 12345',
      reason: 'the old bug: the postcode displaced the city entirely',
    );
    expect(shortenPlace(input), 'Main St, Stockholm');
  });

  test('empty and single-part inputs', () {
    expect(shortenPlace(''), '');
    expect(shortenPlace('   '), '');
    expect(shortenPlace('Arlanda Express'), 'Arlanda Express');
  });
}
