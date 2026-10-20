import 'package:movera_rider/l10n/l10n.dart';
final _postcodeLikeToken = RegExp(r'^\d{3,}(\s?\d{2})?$');

/// Shortens a comma-separated place/address string to its first two
/// meaningful parts, dropping postcode-like numeric tokens (e.g. "123 45").
/// Falls back to the trimmed input when nothing survives the filter.
String shortenPlace(String raw) {
  final clean = L10n.place(raw.trim());
  if (clean.isEmpty) return clean;
  final parts = clean
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .where((part) => !_postcodeLikeToken.hasMatch(part))
      .toList();
  if (parts.isEmpty) return clean;
  if (parts.length == 1) return parts.first;
  return '${parts[0]}, ${parts[1]}';
}

/// UI-08: the stops of a route in one short line, "via Odenplan · KTH", so
/// the rider can see them on every booking step. Null without stops.
String? viaStopsLine(Iterable<String> stops) {
  final names = [
    for (final stop in stops)
      if (stop.trim().isNotEmpty) shortenPlace(stop).split(',').first.trim(),
  ];
  if (names.isEmpty) return null;
  return 'via ${names.join(' · ')}';
}
