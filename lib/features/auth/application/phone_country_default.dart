import 'package:flutter/widgets.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/features/auth/domain/phone_country.dart';

/// The phone field's starting country (owner decision 7), read from the
/// app's saved last good fix, the device's last zone and the device locale:
/// no location prompt is shown for it. See [PhoneCountries.defaultFor].
Future<PhoneCountry> defaultPhoneCountry({
  LocationRepository location = const LocationRepository(),
  String? localeRegion,
}) async {
  final region = localeRegion ?? _deviceRegion();
  try {
    final fix = await location.readLastGoodFix();
    final zone = fix == null ? await LocationRepository.readLastZone() : null;
    return PhoneCountries.defaultFor(
      lastFixLat: fix?.latitude,
      lastFixLng: fix?.longitude,
      lastZone: zone,
      localeRegion: region,
    );
  } catch (_) {
    return PhoneCountries.defaultFor(localeRegion: region);
  }
}

/// The best guess before the saved fix is read: the device's region, else
/// Sweden.
PhoneCountry initialPhoneCountry() =>
    PhoneCountries.defaultFor(localeRegion: _deviceRegion());

/// The country of the device's locale ("SE" in sv-SE or en-SE), or null.
String? _deviceRegion() {
  try {
    return WidgetsBinding.instance.platformDispatcher.locale.countryCode;
  } catch (_) {
    return null;
  }
}
