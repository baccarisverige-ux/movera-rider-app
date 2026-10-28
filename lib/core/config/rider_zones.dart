/// The zones the Rider serves, and which one a pickup is in. Q7 (owner
/// decision): the pickup location decides the zone, and the zone decides
/// the currency.
///
/// Contract v0.11.0 §20 (decision #9, "the server's list is the truth"):
/// on the contract wire the zones are the OPEN zones of `GET /rider/zones`
/// with their outline and names ([RiderZones.useServer]); a pickup is in a
/// zone when the zone's polygon holds it, and a pickup in no open zone is
/// not served ("Movera finns inte här än"). The demo keeps its built-in
/// sample zones ([RiderZones.samples]): one box per country, and every
/// place is served.
class RiderZone {
  const RiderZone({
    required this.id,
    required this.currency,
    required this.timeZone,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    this.names = const {},
    this.country,
    this.kind = 'operating',
    this.polygon,
  });

  final String id;

  /// ISO-4217 code of every price in the zone.
  final String currency;
  final String timeZone;

  /// The zone's bounding box, in degrees.
  final double south;
  final double west;
  final double north;
  final double east;

  /// The zone's name per language (`sv`, `fr`, `en`).
  final Map<String, String> names;
  final String? country;

  /// `operating` (a city zone) or `airport`.
  final String kind;

  /// The outline, `[lat, lng]` points in order, not closed. Null for a
  /// sample zone: its box is its outline.
  final List<List<double>>? polygon;

  bool get isAirport => kind == 'airport';

  /// The name in [languageCode], else English, else any, else the id.
  String nameIn(String languageCode) =>
      names[languageCode] ??
      names['en'] ??
      (names.isEmpty ? id : names.values.first);

  bool _inBox(double lat, double lng) =>
      lat >= south && lat <= north && lng >= west && lng <= east;

  /// True when the zone holds [lat], [lng]: inside its box and its outline
  /// (a point on the edge is inside, contract.json#zones.polygon).
  bool contains(double lat, double lng) {
    if (!_inBox(lat, lng)) return false;
    final outline = polygon;
    if (outline == null) return true;
    return polygonHolds(outline, lat, lng);
  }

  double get _area => (north - south) * (east - west);

  /// A zone of `GET /rider/zones`, or null when [raw] is not one.
  static RiderZone? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['zoneId'];
    final currency = raw['currency'];
    final timeZone = raw['timeZone'];
    if (id is! String || id.isEmpty) return null;
    if (currency is! String || timeZone is! String) return null;
    final points = <List<double>>[];
    final rawPolygon = raw['polygon'];
    if (rawPolygon is! List) return null;
    for (final point in rawPolygon) {
      if (point is! List || point.length < 2) return null;
      final lat = point[0];
      final lng = point[1];
      if (lat is! num || lng is! num) return null;
      points.add([lat.toDouble(), lng.toDouble()]);
    }
    if (points.length < 3) return null;
    final names = <String, String>{};
    final rawNames = raw['names'];
    if (rawNames is Map) {
      rawNames.forEach((key, value) {
        if (key is String && value is String && value.trim().isNotEmpty) {
          names[key] = value.trim();
        }
      });
    }
    var south = points.first[0], north = south;
    var west = points.first[1], east = west;
    for (final p in points) {
      if (p[0] < south) south = p[0];
      if (p[0] > north) north = p[0];
      if (p[1] < west) west = p[1];
      if (p[1] > east) east = p[1];
    }
    final kind = raw['kind'];
    final country = raw['country'];
    return RiderZone(
      id: id,
      currency: currency,
      timeZone: timeZone,
      south: south,
      west: west,
      north: north,
      east: east,
      names: names,
      country: country is String ? country : null,
      kind: kind is String ? kind : 'operating',
      polygon: points,
    );
  }

  Map<String, Object?> toJson() => {
    'zoneId': id,
    'currency': currency,
    'timeZone': timeZone,
    'names': names,
    if (country != null) 'country': country,
    'kind': kind,
    'polygon':
        polygon ??
        [
          [south, west],
          [south, east],
          [north, east],
          [north, west],
        ],
  };
}

/// Point in polygon, a point on an edge inside (ray casting with an edge
/// check first). [outline] is `[lat, lng]` points, not closed.
bool polygonHolds(List<List<double>> outline, double lat, double lng) {
  const eps = 1e-12;
  var inside = false;
  for (var i = 0, j = outline.length - 1; i < outline.length; j = i++) {
    final ay = outline[i][0], ax = outline[i][1];
    final by = outline[j][0], bx = outline[j][1];
    // On the edge a-b?
    final cross = (bx - ax) * (lat - ay) - (by - ay) * (lng - ax);
    if (cross.abs() < eps &&
        lng >= (ax < bx ? ax : bx) - eps &&
        lng <= (ax < bx ? bx : ax) + eps &&
        lat >= (ay < by ? ay : by) - eps &&
        lat <= (ay < by ? by : ay) + eps) {
      return true;
    }
    if ((ay > lat) != (by > lat) &&
        lng < (bx - ax) * (lat - ay) / (by - ay) + ax) {
      inside = !inside;
    }
  }
  return inside;
}

abstract final class RiderZones {
  static const sweden = RiderZone(
    id: 'Z001',
    currency: 'SEK',
    timeZone: 'Europe/Stockholm',
    south: 55.0,
    west: 10.5,
    north: 69.2,
    east: 24.3,
    names: {
      'sv': 'Stockholm län',
      'fr': 'Comté de Stockholm',
      'en': 'Stockholm County',
    },
    country: 'SE',
  );

  static const france = RiderZone(
    id: 'FR-PC',
    currency: 'EUR',
    timeZone: 'Europe/Paris',
    south: 41.3,
    west: -5.3,
    north: 51.2,
    east: 9.7,
    names: {
      'sv': 'Paris & Île-de-France',
      'fr': 'Paris & Île-de-France',
      'en': 'Paris & Île-de-France',
    },
    country: 'FR',
  );

  static const tunisia = RiderZone(
    id: 'TN-TC',
    currency: 'TND',
    timeZone: 'Africa/Tunis',
    south: 30.2,
    west: 7.5,
    north: 37.6,
    east: 11.7,
    names: {'sv': 'Stor-Tunis', 'fr': 'Grand Tunis', 'en': 'Greater Tunis'},
    country: 'TN',
  );

  /// The demo's built-in zones (and the stand-in before the server's list
  /// was ever read): a box per country, every place served.
  static const samples = <RiderZone>[sweden, france, tunisia];

  static List<RiderZone>? _server;

  /// True once the server's list is in use: places outside it are not
  /// served.
  static bool get live => _server != null;

  /// Uses the server's open zones (`GET /rider/zones`, or the kept answer).
  static void useServer(List<RiderZone> zones) {
    _server = List.unmodifiable(zones);
  }

  /// Back to the built-in samples (the demo, and tests).
  static void useSamples() {
    _server = null;
  }

  /// The zones the app knows: the server's, else the samples.
  static List<RiderZone> get all => _server ?? samples;

  /// The home zone: the one a pickup outside every known zone gets for its
  /// currency and clock. On the server's list: its first city zone, Stockholm
  /// when listed.
  static RiderZone get home {
    final zones = _server;
    if (zones == null || zones.isEmpty) return sweden;
    for (final zone in zones) {
      if (zone.id == sweden.id) return zone;
    }
    for (final zone in zones) {
      if (!zone.isAirport) return zone;
    }
    return zones.first;
  }

  /// The zone that takes a ride from [lat], [lng] (contract.json#zones
  /// .lookup): among zones holding it, a city zone before an airport, then
  /// the smallest box. Null outside every zone or without a point.
  static RiderZone? find(double? lat, double? lng) {
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return null;
    }
    RiderZone? best;
    for (final zone in all) {
      if (!zone.contains(lat, lng)) continue;
      if (best == null ||
          (best.isAirport && !zone.isAirport) ||
          (best.isAirport == zone.isAirport && zone._area < best._area)) {
        best = zone;
      }
    }
    return best;
  }

  /// False only when the server's list is in use and [lat], [lng] lies in
  /// none of its open zones: Movera is not there yet. The demo serves
  /// every place; a missing point is not refused here.
  static bool serves(double? lat, double? lng) {
    if (!live) return true;
    if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) {
      return true;
    }
    return find(lat, lng) != null;
  }

  /// The zone of a pickup at [lat], [lng]. Never null: unknown places and a
  /// missing point are the home zone.
  static RiderZone at(double? lat, double? lng) => find(lat, lng) ?? home;

  /// The zone with [id], or null.
  static RiderZone? byId(String? id) {
    for (final zone in all) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  /// The zone whose prices are in [currency], or null.
  static RiderZone? byCurrency(String? currency) {
    for (final zone in all) {
      if (zone.currency == currency && !zone.isAirport) return zone;
    }
    for (final zone in all) {
      if (zone.currency == currency) return zone;
    }
    return null;
  }

  /// The city zones' names in [languageCode], for "Movera is in …".
  static List<String> cityNames(String languageCode) => [
    for (final zone in all)
      if (!zone.isAirport) zone.nameIn(languageCode),
  ];
}
