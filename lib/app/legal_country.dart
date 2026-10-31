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
