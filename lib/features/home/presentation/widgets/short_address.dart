import 'package:movera_rider/l10n/l10n.dart';

/// Truncates an address for compact display, matching home.dart's own
/// `_shortAddress` formatting exactly.
String shortAddress(String? address, {int maxLength = 24}) {
  final value = L10n.place(address?.trim() ?? '');
  if (value.isEmpty) return L10n.current.setLocation;
  return value.length <= maxLength
      ? value
      : '${value.substring(0, maxLength - 1)}…';
}
