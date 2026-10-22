import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/features/safety/domain/phone_e164.dart';

part 'phone_country_list.dart';

/// A country of the sign-in phone field (owner decision 7): its ISO 3166-1
/// code, its international dial code and its name.
class PhoneCountry {
  const PhoneCountry(this.iso, this.dial, this.name, {this.fr, this.sv});

  /// ISO 3166-1 alpha-2, upper case (`SE`).
  final String iso;

  /// The dial code without the plus (`46`).
  final String dial;

  /// The English name.
  final String name;

  /// The French and Swedish names, where the app has them.
  final String? fr;
  final String? sv;

  /// `+46`.
  String get dialLabel => '+$dial';

  /// The flag emoji, from the ISO code's regional indicator letters.
  String get flag => String.fromCharCodes([
        for (final unit in iso.codeUnits) 0x1F1E6 + unit - 0x41,
      ]);

  /// The name in [language] (`en`, `fr`, `sv`), English when the app has
  /// no translation.
  String nameIn(String language) => switch (language) {
        'fr' => fr ?? name,
        'sv' => sv ?? name,
        _ => name,
      };

  @override
  String toString() => 'PhoneCountry($iso, +$dial)';
}

abstract final class PhoneCountries {
  /// Every country the phone field offers.
  static const List<PhoneCountry> all = _countries;

  static final PhoneCountry sweden = byIso('SE')!;
  static final PhoneCountry france = byIso('FR')!;
  static final PhoneCountry tunisia = byIso('TN')!;

  static PhoneCountry? byIso(String? iso) {
    final code = iso?.trim().toUpperCase();
    for (final country in _countries) {
      if (country.iso == code) return country;
    }
    return null;
  }

  /// The country of a Rider zone.
  static PhoneCountry ofZone(RiderZone zone) => switch (zone.id) {
        'FR-PC' => france,
        'TN-TC' => tunisia,
        _ => sweden,
      };

  /// The zone country whose box holds [lat], [lng], or null: unlike
  /// [RiderZones.at], a place outside every zone is not the home zone.
  static PhoneCountry? atPoint(double? lat, double? lng) {
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return null;
    }
    for (final zone in RiderZones.all) {
      if (zone.contains(lat, lng)) return ofZone(zone);
    }
    return null;
  }

  /// The phone field's starting country, from what the app already knows
  /// without asking for location:
  /// 1. the app's last good fix, when it lies in a zone country;
  /// 2. with no fix, the zone of the last fix this device ever had (a fix
  ///    outside every zone was saved as the home zone, so it is skipped
  ///    when the fix itself is known to be elsewhere);
  /// 3. the device's region (the country of its locale);
  /// 4. Sweden, the home zone's country.
  static PhoneCountry defaultFor({
    double? lastFixLat,
    double? lastFixLng,
    RiderZone? lastZone,
    String? localeRegion,
  }) {
    final hasFix = lastFixLat != null && lastFixLng != null;
    final fromLocation = hasFix
        ? atPoint(lastFixLat, lastFixLng)
        : (lastZone == null ? null : ofZone(lastZone));
    return fromLocation ?? byIso(localeRegion) ?? sweden;
  }

  /// The countries whose name (English or in [language]) or ISO code
  /// matches [query], or whose dial code starts with its digits ("+21",
  /// "216"), sorted by their name in [language].
  static List<PhoneCountry> search(String query, String language) {
    final q = fold(query.trim());
    final dial = q.startsWith('+') ? q.substring(1) : q;
    final byDial = RegExp(r'^\d+$').hasMatch(dial);
    final matches = [
      for (final c in _countries)
        if (q.isEmpty ||
            (byDial
                ? c.dial.startsWith(dial)
                : fold(c.nameIn(language)).contains(q) ||
                    fold(c.name).contains(q) ||
                    c.iso.toLowerCase() == q))
          c,
    ];
    matches.sort(
      (a, b) => fold(a.nameIn(language)).compareTo(fold(b.nameIn(language))),
    );
    return matches;
  }

  static const Map<String, String> _plain = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
    'ç': 'c', 'ć': 'c', 'č': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ł': 'l', 'ñ': 'n', 'ò': 'o',
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'š': 's', 'ù': 'u',
    'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ž': 'z', 'æ': 'ae',
    'œ': 'oe', '’': "'",
  };

  /// [text] in lower case without accents, so "tunisie" finds "Tunisie"
  /// and "etats" finds "États-Unis".
  static String fold(String text) => text
      .toLowerCase()
      .split('')
      .map((ch) => _plain[ch] ?? ch)
      .join();

  /// The country a number in international form (`+33…`, `0033…`) dials,
  /// by the longest matching dial code; [preferred] wins a shared code
  /// (+1, +7, +44…). Null for national input or an unknown code.
  static PhoneCountry? ofInternational(String digits, {PhoneCountry? preferred}) {
    if (preferred != null && digits.startsWith(preferred.dial)) {
      return preferred;
    }
    PhoneCountry? best;
    for (final c in _countries) {
      if (digits.startsWith(c.dial) &&
          (best == null || c.dial.length > best.dial.length)) {
        best = c;
      }
    }
    return best;
  }
}

/// The national length of a mobile number in the zone countries, for
/// recognising a pasted number that carries its dial code without a plus.
const Map<String, int> _mobileLength = {'SE': 9, 'FR': 9, 'TN': 8};

/// [country]'s mobile number length without the trunk 0, where the app
/// knows it (Sweden, France, Tunisia).
int? mobileLengthOf(PhoneCountry country) => _mobileLength[country.iso];

/// An example national number for the field's hint.
String phoneHintOf(PhoneCountry country) => switch (country.iso) {
      'SE' => '70 123 45 67',
      'FR' => '6 12 34 56 78',
      'TN' => '20 123 456',
      _ => '',
    };

final RegExp _separators = RegExp(r'[\s\-(). ]');

/// The E.164 mobile number a rider typed for [country], or null.
///
/// Accepts the national form with or without the trunk 0 ("070 123 45 67",
/// "70 123 45 67") and the international forms (+46 …, 0046 …, and for the
/// zone countries a bare 46 … of full length). An international number of
/// another country is checked by that country's rule.
///
/// Rules: Sweden (+46) a mobile, 7 and eight more digits (rider-r3-11);
/// France (+33) 6 or 7 and eight more; Tunisia (+216) eight digits starting
/// 2, 4, 5 or 9; anywhere else a national number of 4–14 digits, 7–15
/// digits in all (the contract's `^\+[1-9]\d{6,14}$`).
String? phoneNumberFromField(String typed, PhoneCountry country) {
  var raw = typed.replaceAll(_separators, '');
  if (raw.isEmpty) return null;
  var target = country;
  String national;
  if (raw.startsWith('+') || raw.startsWith('00')) {
    raw = raw.startsWith('+') ? raw.substring(1) : raw.substring(2);
    if (!RegExp(r'^\d+$').hasMatch(raw)) return null;
    final dialled = PhoneCountries.ofInternational(raw, preferred: country);
    if (dialled == null) return null;
    target = dialled;
    // "+46 (0)70 …": the bracketed trunk 0 went with the separators and
    // is dropped below.
    national = raw.substring(dialled.dial.length);
  } else {
    if (!RegExp(r'^\d+$').hasMatch(raw)) return null;
    national = raw;
    final length = _mobileLength[country.iso];
    if (length != null &&
        !raw.startsWith('0') &&
        raw.startsWith(country.dial) &&
        raw.length >= country.dial.length + length) {
      national = raw.substring(country.dial.length);
    }
  }
  if (national.startsWith('0')) national = national.substring(1);
  if (!_validNational(target, national)) return null;
  return '+${target.dial}$national';
}

bool _validNational(PhoneCountry country, String national) {
  switch (country.iso) {
    case 'SE':
      return RegExp(r'^7\d{8}$').hasMatch(national);
    case 'FR':
      return RegExp(r'^[67]\d{8}$').hasMatch(national);
    case 'TN':
      return RegExp(r'^[2459]\d{7}$').hasMatch(national);
  }
  final total = country.dial.length + national.length;
  return RegExp(r'^[1-9]\d{3,13}$').hasMatch(national) &&
      total >= 7 &&
      total <= 15;
}

/// [e164] grouped for reading: "+46 70 123 45 67", "+33 6 12 34 56 78",
/// "+216 20 123 456", else the dial code and the national number.
String displayPhoneNumber(String e164) {
  final value = e164.trim();
  if (!value.startsWith('+')) return value;
  if (value.startsWith('+46')) return SwedishPhone.display(value);
  final digits = value.substring(1);
  final country = PhoneCountries.ofInternational(digits);
  if (country == null) return value;
  final national = digits.substring(country.dial.length);
  if (national.isEmpty) return value;
  String grouped;
  if (country.iso == 'FR' && national.length == 9) {
    grouped = '${national[0]} ${national.substring(1, 3)} '
        '${national.substring(3, 5)} ${national.substring(5, 7)} '
        '${national.substring(7)}';
  } else if (country.iso == 'TN' && national.length == 8) {
    grouped = '${national.substring(0, 2)} ${national.substring(2, 5)} '
        '${national.substring(5)}';
  } else {
    grouped = national;
  }
  return '+${country.dial} $grouped';
}
