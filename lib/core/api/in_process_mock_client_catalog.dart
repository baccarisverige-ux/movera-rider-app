part of 'in_process_mock_client.dart';

/// The ride categories a fresh mock starts with (see [InProcessMockClient.rideTypes]).
List<Map<String, dynamic>> _seedRideTypes() => [
  _rideType(
    'economy',
    'Movera',
    4,
    8,
    259,
    'Affordable and convenient rides',
    order: 1,
    badge: 'RECOMMENDED',
  ),
  _rideType(
    'comfort',
    'Comfort',
    4,
    11,
    339,
    'Newer cars with extra legroom',
    order: 2,
  ),
  _rideType(
    'premium',
    'Premium',
    4,
    11,
    369,
    'Premium cars with top-rated drivers',
    order: 3,
  ),
  _rideType(
    'priority',
    'Priority',
    4,
    6,
    289,
    'More options, less waiting',
    order: 4,
    badge: 'FASTER',
  ),
  _rideType(
    'xl',
    'Movera XL',
    6,
    12,
    399,
    'Cars for larger groups (6 people)',
    order: 5,
  ),
  _rideType(
    'electric',
    'Electric',
    4,
    9,
    259,
    'Quiet and fossil-free cars',
    order: 6,
    glyph: 'bolt',
  ),
  _rideType(
    'pet',
    'Movera Pet',
    4,
    10,
    279,
    'Pet-friendly rides',
    order: 7,
    glyph: 'pets',
  ),
  _rideType(
    'van',
    'Van',
    8,
    14,
    449,
    'Groups and luggage',
    order: 8,
    glyph: 'van',
  ),
  _rideType(
    'wheelchair',
    'Wheelchair',
    4,
    15,
    289,
    'Ramp or lift, driver helps on board',
    order: 9,
    glyph: 'wheelchair',
  ),
  _rideType(
    'business',
    'Business',
    4,
    10,
    399,
    'Quiet ride, receipt for your company',
    order: 10,
    glyph: 'briefcase',
  ),
  _rideType(
    'airport',
    'Airport',
    4,
    12,
    429,
    'Fixed price, flight tracked, extra luggage',
    order: 11,
    glyph: 'plane',
  ),
  _rideType(
    'child_seat',
    'Kids seat',
    4,
    12,
    279,
    'Child seat already fitted',
    order: 12,
    glyph: 'child',
  ),
  _rideType(
    'women',
    'Women driver',
    4,
    13,
    279,
    'A woman behind the wheel',
    order: 13,
    glyph: 'person',
  ),
  _rideType(
    'delivery',
    'Delivery',
    2,
    9,
    199,
    'Send a parcel across town',
    order: 14,
    glyph: 'parcel',
  ),
];

Map<String, dynamic> _rideType(
  String id,
  String name,
  int seats,
  int etaMin,
  int price,
  String description, {
  required int order,
  String? badge,
  String? glyph,
  String? imageKey,
  bool enabled = true,
}) {
  return {
    'id': id,
    'name': name,
    'seats': seats,
    'etaMin': etaMin,
    // The list price as Money (contract v0.3.0).
    'price': _money(price * Money.minorPerMajor(InProcessMockClient.currency)),
    'description': description,
    'badge': badge,
    'glyph': glyph,
    'imageKey': imageKey ?? id,
    'order': order,
    'enabled': enabled,
  };
}

extension _MockCatalog on InProcessMockClient {
  /// Catalog price in kr for [rideType]: the ride-types table first, then
  /// the dev fallback table.
  int _catalogPriceKr(String rawType) {
    final rideType = CategoryIds.canonical(rawType);
    for (final type in rideTypes) {
      if (type['id'] == rideType) {
        final price = type['price'];
        if (price is Map && price['amountMinor'] is int) {
          return (price['amountMinor'] as int) ~/ 100;
        }
        if (price is num) return price.round();
      }
    }
    return mockCatalogPricesKr[rideType] ?? 259;
  }

  /// Loads the trips an earlier launch saved, once per mock instance.
  Future<void> _restoreRidesOnce() async {
    if (_ridesRestored) return;
    _ridesRestored = true;
    try {
      final raw = (await PreferencesStore.load()).getString(
        InProcessMockClient.ridesStorageKey,
      );
      if (raw == null) return;
      final saved = jsonDecode(raw);
      if (saved is! Map) return;
      final trips = saved['rides'];
      if (trips is Map) {
        for (final entry in trips.entries) {
          if (entry.value is Map) {
            rides.putIfAbsent(
              '${entry.key}',
              () => Map<String, dynamic>.from(entry.value as Map),
            );
          }
        }
      }
      final accepted = saved['acceptedAt'];
      if (accepted is Map) {
        for (final entry in accepted.entries) {
          final at = WireTime.tryParse(entry.value);
          if (at != null) _acceptedAt.putIfAbsent('${entry.key}', () => at);
        }
      }
      final endedEarly = saved['endedEarly'];
      if (endedEarly is List) {
        _endedEarly.addAll(endedEarly.whereType<String>());
      }
      // rider-r5-2: the on-board distance (R-O1) and the accepted pickup
      // (rider-u13) are server state too; a reload must not reset them.
      final driven = saved['driven'];
      if (driven is Map) {
        for (final entry in driven.entries) {
          final v = entry.value;
          if (v is Map &&
              v['lat'] is num &&
              v['lng'] is num &&
              v['meters'] is num) {
            _driven.putIfAbsent(
              '${entry.key}',
              () => (
                lat: (v['lat'] as num).toDouble(),
                lng: (v['lng'] as num).toDouble(),
                meters: (v['meters'] as num).toDouble(),
              ),
            );
          }
        }
      }
      final pickups = saved['acceptedPickup'];
      if (pickups is Map) {
        for (final entry in pickups.entries) {
          final v = entry.value;
          if (v is Map && v['lat'] is num && v['lng'] is num) {
            _acceptedPickup.putIfAbsent(
              '${entry.key}',
              () => (
                lat: (v['lat'] as num).toDouble(),
                lng: (v['lng'] as num).toDouble(),
              ),
            );
          }
        }
      }
      _savedRides = raw;
    } catch (error) {
      AppLog.warning('mock.rides_restore_failed', extra: {'error': '$error'});
    }
  }

  /// Saves the newest trips when a request changed them.
  Future<void> _persistRides() async {
    try {
      final keep = rides.keys.toList();
      final recent = keep.length > InProcessMockClient.persistedRidesLimit
          ? keep.sublist(keep.length - InProcessMockClient.persistedRidesLimit)
          : keep;
      final encoded = jsonEncode({
        'rides': {for (final id in recent) id: rides[id]},
        'acceptedAt': {
          for (final id in recent)
            if (_acceptedAt[id] case final at?) id: WireTime.format(at),
        },
        'endedEarly': [
          for (final id in recent)
            if (_endedEarly.contains(id)) id,
        ],
        'driven': {
          for (final id in recent)
            if (_driven[id] case final d?)
              id: {'lat': d.lat, 'lng': d.lng, 'meters': d.meters},
        },
        'acceptedPickup': {
          for (final id in recent)
            if (_acceptedPickup[id] case final p?)
              id: {'lat': p.lat, 'lng': p.lng},
        },
      });
      if (encoded == _savedRides) return;
      _savedRides = encoded;
      await (await PreferencesStore.load()).setString(
        InProcessMockClient.ridesStorageKey,
        encoded,
      );
    } catch (error) {
      AppLog.warning('mock.rides_persist_failed', extra: {'error': '$error'});
    }
  }
}
