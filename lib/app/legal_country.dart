import 'package:movera_rider/core/config/trip_zone_config.dart';
import 'package:movera_rider/features/auth/application/phone_country_default.dart';

/// Contract v0.18.5 `legal.apps`: the country whose terms the app shows:
/// the rider's zone country when it is Sweden or France, else the start
/// country of the sign-in screen (`auth.startCountry`: SE or FR).
Future<String> riderLegalCountry() async {
  try {
    final zone = await currentRiderZone();
    final country = zone.country;
    if (country == 'SE' || country == 'FR') return country!;
  } catch (_) {
    // The start country below.
  }
  final start = (await defaultPhoneCountry()).iso;
  return start == 'FR' ? 'FR' : 'SE';
}

/// G6 (contract v0.18.8): the zone sent as `?zoneId=` with the terms so
/// paragraph 3.5 shows its live waiting / no-show numbers; only a zone of
/// the terms' own [country] (another country's zone leaves 3.5 out).
Future<String?> riderLegalZoneId(String country) async {
  try {
    final zone = await currentRiderZone();
    return zone.country == country ? zone.id : null;
  } catch (_) {
    return null;
  }
}
