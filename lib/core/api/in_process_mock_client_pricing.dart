part of 'in_process_mock_client.dart';

/// Money on the wire, in [code] (the home currency unless a trip or a
/// zone says otherwise).
Map<String, Object> _money(
  int amountMinor, [
  String code = InProcessMockClient.currency,
]) => {'amountMinor': amountMinor, 'currency': code};

/// Q7: the currency of a stored trip, set at booking from its quote (the
/// pickup's zone): its fare's, else its flat `currency`, else the home
/// currency (a trip a test seeded by hand).
String _currencyOf(Map<String, dynamic> ride) {
  final fare = ride['fare'];
  final code =
      Money.normalizeCurrency(fare is Map ? fare['currency'] : null) ??
      Money.normalizeCurrency(ride['currency']);
  return code ?? InProcessMockClient.currency;
}

/// Q7: the zone of the pickup a request names (`pickupLat`/`pickupLng`).
RiderZone _zoneOf(Map<String, dynamic> body) => RiderZones.at(
  (body['pickupLat'] as num?)?.toDouble(),
  (body['pickupLng'] as num?)?.toDouble(),
);

/// The trip fare in minor units (`fare: Money`). A ride a test seeded
/// with the pre-v0.3 whole-unit `price` is read once from it.
int? _fareMinor(Map<String, dynamic> ride) {
  final fare = ride['fare'];
  if (fare is Map && fare['amountMinor'] is int) {
    return fare['amountMinor'] as int;
  }
  final legacy = ride['price'];
  return legacy is num
      ? Money.fromLegacyMajor(legacy, _currencyOf(ride)).amountMinor
      : null;
}

/// The fare at booking, before offers and route changes.
int? _bookedMinor(Map<String, dynamic> ride) {
  final booked = ride['bookedFare'];
  if (booked is Map && booked['amountMinor'] is int) {
    return booked['amountMinor'] as int;
  }
  final legacy = ride['bookedPrice'];
  return legacy is num
      ? Money.fromLegacyMajor(legacy, _currencyOf(ride)).amountMinor
      : _fareMinor(ride);
}

/// rider-u14: every offer raise the rider made while searching, summed.
int _offerRaisedMinor(Map<String, dynamic> ride) {
  final raised = ride['offerRaised'];
  return raised is Map && raised['amountMinor'] is int
      ? raised['amountMinor'] as int
      : 0;
}

/// Contract money on the wire: `fare: Money` in the trip's currency,
/// never whole-unit doubles.
void _setFare(Map<String, dynamic> ride, int amountMinor) {
  ride['fare'] = _money(amountMinor, _currencyOf(ride));
  ride.remove('price');
}

/// The rider's offer raise as minor units: `offerIncrease: Money` in the
/// trip's currency [code], or the pre-v0.3 whole-kronor `offerIncreaseKr`
/// (compatibility, kronor trips only). Null when it is not positive and
/// on the zone's price step (a whole krona, 0.05 €, 0.1 DT).
int? _offerIncreaseMinor(Map<String, dynamic> body, String code) {
  final step = MockZoneCurrency.of(code).stepMinor;
  final money = body['offerIncrease'];
  if (money is Map) {
    final minor = money['amountMinor'];
    if (minor is int &&
        minor > 0 &&
        minor % step == 0 &&
        money['currency'] == code) {
      return minor;
    }
    return null;
  }
  final kr = body['offerIncreaseKr'];
  if (code == InProcessMockClient.currency &&
      kr is num &&
      kr > 0 &&
      kr == kr.roundToDouble()) {
    return Money.fromLegacyMajor(kr, code).amountMinor;
  }
  return null;
}

/// A route-change price on the wire: Money plus the flat minor fields
/// (next to `currency`), no whole-unit doubles.
Map<String, Object?> _pricingWire(Map<String, dynamic> pricing) {
  final newMinor = pricing['newMinor'] as int;
  final differenceMinor = pricing['differenceMinor'] as int;
  final code = pricing['currency'] as String;
  return {
    'newTotal': _money(newMinor, code),
    'difference': _money(differenceMinor, code),
    'newTotalMinor': newMinor,
    'differenceMinor': differenceMinor,
    'currency': code,
    'routeKm': pricing['routeKm'],
    'stops': pricing['stops'],
  };
}

/// The route a route quote priced, to compare with the one applied.
String _routeFingerprint(Map<String, dynamic> body) => jsonEncode([
  body['pickupLat'],
  body['pickupLng'],
  body['destinationLat'],
  body['destinationLng'],
  [
    if (body['stops'] is List)
      for (final raw in body['stops'] as List)
        if (raw is Map) [raw['lat'], raw['lng']],
  ],
]);

double _km(num lat1, num lng1, num lat2, num lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// The catalog price covers a trip this long ([MockCategoryRates]).
const _catalogTripMeters = MockCategoryRates.includedMeters;

/// A stop this close to a booked stop is that booked stop (contract §3).
const _sameStopMeters = 50;

/// How many of the new route's [stops] were not booked: each booked stop
/// (`bookedStops`, else the trip's `stops`) matches one new stop within
/// [_sameStopMeters], once.
int _unbookedStops(
  Map<String, dynamic> ride,
  List<Map<String, dynamic>> stops,
) {
  final bookedRaw = ride['bookedStops'] ?? ride['stops'];
  final booked = [
    if (bookedRaw is List)
      for (final raw in bookedRaw)
        if (raw is Map && raw['lat'] is num && raw['lng'] is num) raw,
  ];
  var unbooked = 0;
  for (final stop in stops) {
    final match = booked.indexWhere(
      (b) =>
          _km(
                b['lat'] as num,
                b['lng'] as num,
                stop['lat'] as num,
                stop['lng'] as num,
              ) *
              1000 <=
          _sameStopMeters,
    );
    if (match < 0) {
      unbooked++;
    } else {
      booked.removeAt(match);
    }
  }
  return unbooked;
}

/// Pickup → stops → destination in kilometres, or null without the points.
double? _routedKm(Map<String, dynamic> body) {
  final points = <List<num>>[];
  void add(Object? lat, Object? lng) {
    if (lat is num && lng is num) points.add([lat, lng]);
  }

  add(body['pickupLat'], body['pickupLng']);
  if (points.isEmpty) return null;
  if (body['stops'] is List) {
    for (final raw in body['stops'] as List) {
      if (raw is Map) add(raw['lat'], raw['lng']);
    }
  }
  final before = points.length;
  add(body['destinationLat'], body['destinationLng']);
  if (points.length == before) return null;
  var km = 0.0;
  for (var i = 1; i < points.length; i++) {
    km += _km(points[i - 1][0], points[i - 1][1], points[i][0], points[i][1]);
  }
  return km;
}

/// rider-r4-5: `pickup` / `dropoff` as openapi `Place`s, from the flat
/// legacy fields every write here still updates. Called again after each
/// change of those fields so the two shapes never disagree.
Map<String, dynamic> _withPlaces(Map<String, dynamic> ride) {
  for (final (place, flat) in const [
    ('pickup', 'pickup'),
    ('dropoff', 'destination'),
  ]) {
    final lat = ride['${flat}Lat'];
    final lng = ride['${flat}Lng'];
    if (lat is num && lng is num) {
      ride[place] = {
        'address': ride['${flat}Address']?.toString() ?? '',
        'lat': lat,
        'lng': lng,
      };
    }
  }
  return ride;
}

/// openapi `PaymentMethod` for a client method id (`card_…` and `cards`
/// are saved cards; `apple` is the v0.3 alias; no Google Pay since v0.18.10).
String _paymentMethodKind(String id) {
  final value = id.trim().toLowerCase();
  if (value == 'apple' || value == 'apple_pay') return 'apple_pay';
  if (value == 'cash' || value == 'wallet') return value;
  return 'card';
}

/// The booked fare in [code]: `fare: Money`, else the pre-v0.3
/// whole-unit `price`, else the quote total.
int? _bookingFareMinor(Map<String, dynamic> body, String code) {
  final fare = body['fare'];
  if (fare is Map && fare['amountMinor'] is int) {
    return fare['amountMinor'] as int;
  }
  final price = body['price'];
  if (price is num) return Money.fromLegacyMajor(price, code).amountMinor;
  final quoted = body['quoteTotalMinor'];
  return quoted is int ? quoted : null;
}

extension _MockPricing on InProcessMockClient {
  /// The stand-in's rates for [category] in [code] ([MockZoneRates]).
  MockZoneRates _ratesFor(String category, String code) =>
      MockZoneRates(catalogKronor: _catalogPriceKr(category), currency: code);

  /// The config document cancel fees are charged from for a trip in
  /// [code]: [riderConfig] when it is in that currency (tests replace it),
  /// else the seed of the zone with that currency.
  RiderAppConfig _configFor(String code) => riderConfig.currency == code
      ? riderConfig
      : SeedRiderConfigRepository.seedForCurrency(code) ?? riderConfig;

  /// ARCH-14: an apply that names a route quote must match it: same ride,
  /// same route, not expired, and the price the rider confirmed is still the
  /// price. Without a route quote id the old contract still applies.
  String? _routeQuoteDenied(
    String rideId,
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final quoteId = body['routeQuoteId'];
    if (quoteId == null) return null;
    final quote = routeQuotes[quoteId];
    if (quote == null || quote['rideId'] != rideId) {
      return 'route_quote_not_found';
    }
    final expiresAt = DateTime.tryParse(quote['expiresAt'] as String? ?? '');
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
      return 'route_quote_expired';
    }
    if (quote['route'] != _routeFingerprint(body)) {
      return 'route_quote_mismatch';
    }
    final quoted = quote['newTotalMinor'] as int;
    final expected = (body['expectedTotalMinor'] as num?)?.round();
    final now = _routeChangePricing(ride, body)['newMinor'] as int;
    if ((expected != null && expected != quoted) || now != quoted) {
      return 'route_quote_price_changed';
    }
    return null;
  }

  /// New price for a changed route (contract §3 "Route-change pricing"):
  /// the booked price with the offer raises, plus 25 kr per stop that was
  /// not booked and 12 kr per kilometre beyond the booked route through its
  /// stops, in the trip's currency ([MockZoneRates]: 2.40 € and 1.15 € in Paris). Shorter routes
  /// get the difference back. Minor units, on the zone's price step.
  ///
  /// rider-9 / owner decision 5: a booked stop is counted once. The booked
  /// kilometres already go through it and the booking charged it no stop
  /// fee, so keeping it costs nothing more.
  ///
  /// rider-u14: the rider's offer raises are part of every new route's
  /// price, so a route change never takes back the raise the driver
  /// accepted.
  Map<String, dynamic> _routeChangePricing(
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final code = _currencyOf(ride);
    final rates = _ratesFor(
      (ride['categoryId'] ?? ride['rideType'] ?? '').toString(),
      code,
    );
    final baseMinor = (_bookedMinor(ride) ?? 0) + _offerRaisedMinor(ride);
    final pLat = (body['pickupLat'] ?? ride['pickupLat']) as num?;
    final pLng = (body['pickupLng'] ?? ride['pickupLng']) as num?;
    final dLat = body['destinationLat'] as num;
    final dLng = body['destinationLng'] as num;
    final stops = <Map<String, dynamic>>[
      if (body['stops'] is List)
        for (final raw in body['stops'] as List)
          if (raw is Map && raw['lat'] is num && raw['lng'] is num)
            {
              'address': raw['address']?.toString() ?? '',
              'lat': raw['lat'],
              'lng': raw['lng'],
            },
    ];
    final routeKm =
        _routedKm({
          'pickupLat': pLat,
          'pickupLng': pLng,
          'stops': stops,
          'destinationLat': dLat,
          'destinationLng': dLng,
        }) ??
        0;
    final bookedKm = (ride['bookedKm'] as num?)?.toDouble() ?? routeKm;
    final newMinor = rates.roundToStep(
      (baseMinor +
              _unbookedStops(ride, stops) * rates.convertKronor(25) +
              (routeKm - bookedKm) * rates.perKmMinor)
          .clamp(baseMinor * 0.5, double.infinity),
    );
    final currentMinor = _fareMinor(ride) ?? baseMinor;
    return {
      'newMinor': newMinor,
      'differenceMinor': newMinor - currentMinor,
      'currency': code,
      'routeKm': double.parse(routeKm.toStringAsFixed(2)),
      'stops': stops,
    };
  }

  /// Pickup → stops → destination in metres, or null without the points.
  int? _routedMeters(Map<String, dynamic> body) {
    final km = _routedKm(body);
    return km == null ? null : math.max(1, (km * 1000).round());
  }

  Map<String, dynamic> _quote(Map<String, dynamic> body) {
    // Contract v0.3.0: canonical category id; `movera` is read as `economy`.
    final rideType = CategoryIds.canonical(
      body['rideType'] as String? ?? CategoryIds.economy,
    );
    // ARCH-8 / contract C-2: price the route from the points (through the
    // stops) like a server would; the client's distance is only a hint for
    // callers that send no points.
    final distanceMeters =
        _routedMeters(body) ??
        (body['distanceMeters'] as num?)?.round() ??
        _catalogTripMeters;
    // Q7: the pickup's zone decides the currency, and the price is the
    // zone's own ([MockZoneRates]), not a converted kronor amount.
    final zone = _zoneOf(body);
    final rates = _ratesFor(rideType, zone.currency);
    final catalogMinor = rates.listMinor;
    final fullMinor = rates.quote(distanceMeters).amountMinor;
    // Demo promotion: discounts the ride types it names, capped per ride
    // (the cap is in kronor, so it is the zone's own amount elsewhere).
    final promo = activePromotion;
    final eligible =
        promo != null &&
        (promo['rideTypes'] as List? ?? const []).contains(rideType);
    final cap = (promo?['maxDiscountMinor'] as num?)?.round();
    final discountMinor = eligible
        ? ((fullMinor * (promo['percentOff'] as num) / 100).round()).clamp(
            0,
            cap == null
                ? fullMinor
                : rates.convertKronor(
                    Money(cap, InProcessMockClient.currency).major,
                  ),
          )
        : 0;
    final minor = fullMinor - discountMinor;
    final id = 'q_${rideType}_${newRequestId()}';
    return {
      'id': id,
      'quoteId': id,
      'rideType': rideType,
      // Contract v0.3.0 Quote.total; the flat minor fields sit next to
      // `currency` for pre-v0.3 readers.
      'total': _money(minor, zone.currency),
      'totalMinor': minor,
      'amountMinor': minor,
      'currency': zone.currency,
      'zoneId': zone.id,
      // ARCH-11: RFC 3339 UTC with offset, like a real server.
      'expiresAt': WireTime.format(
        DateTime.now().add(const Duration(minutes: 2)),
      ),
      'expiresInSec': 120,
      'breakdown': {
        'baseMinor': math.min(fullMinor, catalogMinor),
        'distanceMinor': math.max(0, fullMinor - catalogMinor),
        'timeMinor': 0,
        'bookingFeeMinor': 0,
        'discountMinor': discountMinor,
      },
      'signedPayload': 'mock-api',
      'pickup': body['pickup'],
      'destination': body['destination'],
    };
  }

  String? _validateQuoteBinding(Map<String, dynamic> body) {
    // RIDE-22: a scheduled booking that carries a quote is held to it; one
    // without (the older contract) is still accepted.
    if (body['scheduledAt'] != null && body['quoteId'] == null) return null;
    if (body['pickupAddress'] == null) return null;

    final quoteId = body['quoteId'] as String?;
    final signed = body['quoteSignedPayload'] as String?;
    final expiryRaw = body['quoteExpiresAt'] as String?;
    final quotedTotal = (body['quoteTotalMinor'] as num?)?.round();
    if (quoteId == null ||
        quoteId.isEmpty ||
        signed == null ||
        signed.isEmpty ||
        expiryRaw == null ||
        quotedTotal == null) {
      return 'quote_required';
    }

    final quote = quotes[quoteId];
    if (quote == null) return 'quote_not_found';
    if (quote['signedPayload'] != signed) return 'quote_signature_mismatch';

    final expiresAt = DateTime.tryParse(expiryRaw);
    final serverExpiry = DateTime.tryParse(quote['expiresAt'] as String? ?? '');
    if (expiresAt == null ||
        serverExpiry == null ||
        expiresAt.toUtc() != serverExpiry.toUtc() ||
        !serverExpiry.isAfter(DateTime.now())) {
      return 'quote_expired';
    }

    final serverTotal = (quote['totalMinor'] as num?)?.round();
    if (serverTotal == null || serverTotal != quotedTotal) {
      return 'quote_amount_mismatch';
    }
    final quoteCurrency =
        (quote['currency'] as String?) ?? InProcessMockClient.currency;

    final categoryId = CategoryIds.canonical(
      (body['categoryId'] ?? '').toString(),
    );
    if (quote['rideType'] != categoryId) return 'quote_category_mismatch';

    // The fare the rider confirmed: `fare: Money` in the quote's currency,
    // or the pre-v0.3 whole-unit `price` (compatibility).
    final fare = body['fare'];
    if (fare is Map && fare['currency'] != quoteCurrency) {
      return 'quote_price_mismatch';
    }
    final submittedMinor = fare is Map && fare['amountMinor'] is int
        ? fare['amountMinor'] as int
        : (body['price'] is num
              ? Money.fromLegacyMajor(
                  body['price'] as num,
                  quoteCurrency,
                ).amountMinor
              : null);
    if (submittedMinor == null || submittedMinor != serverTotal) {
      return 'quote_price_mismatch';
    }

    // "Use wallet balance first" (contract C-3): the wallet part may not
    // exceed the fare, and is zero when the rider switched it off.
    final walletMinor = (body['walletAmountMinor'] as num?)?.round() ?? 0;
    final walletFirst = body['useWalletFirst'] == true;
    // Q8: one wallet per currency; the wallet part is in the trip's own
    // currency (the quote's minor units), never converted.
    if (walletMinor < 0 ||
        walletMinor > serverTotal ||
        (!walletFirst && walletMinor != 0)) {
      return 'wallet_amount_invalid';
    }

    return null;
  }

  Map<String, dynamic> _ride(Map<String, dynamic> body, String requestId) {
    final categoryId = CategoryIds.canonical(
      (body['categoryId'] ?? body['rideType'] ?? CategoryIds.economy)
          .toString(),
    );
    final paymentMethodId =
        (body['paymentMethodId'] ?? body['paymentMethod'] ?? 'wallet')
            .toString();
    final scheduled = body['scheduledAt'] != null;
    // The server walks the new trip draft → quoted → requested (→ searching
    // for a live trip) through the transition table; the client reads the
    // status from this response and never assumes it.
    var tripStatus = TripStatus.draft;
    for (final (command, actor) in [
      ('quote', TripActor.system),
      ('request', TripActor.rider),
      if (!scheduled) ('start_search', TripActor.system),
    ]) {
      tripStatus = TripStateMachine.apply(
        tripStatus,
        command,
        actor,
        kind: scheduled ? TripKind.scheduled : TripKind.live,
      )!;
    }
    final id = 'ride_$requestId';
    final code = _bookingCurrency(body);
    final bookedStops = <Map<String, dynamic>>[
      if (body['stops'] is List)
        for (final raw in body['stops'] as List)
          if (raw is Map && raw['lat'] is num && raw['lng'] is num)
            {
              'address': raw['address']?.toString() ?? '',
              'lat': raw['lat'],
              'lng': raw['lng'],
            },
    ];
    return _withPlaces({
      'id': id,
      'tripId': id,
      // Legacy read-only alias of tripId during migration.
      'rideId': id,
      // rider-r4-5: the openapi TripProjection required fields the legacy
      // keys below do not cover. One stand-in rider; the pickup's zone.
      'riderId': InProcessMockClient.mockRiderId,
      'zoneId': _zoneOf(body).id,
      'pinRequired': false,
      'kind': scheduled ? TripKind.scheduled.wireName : TripKind.live.wireName,
      'status': tripStatus.wireName,
      'ratingStatus': TripRatingStatus.notRequested.wireName,
      'version': 1,
      'sequence': 1,
      'eventId': 'ev_${id}_1',
      'eventKind': 'trip_projection',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      // Contract v0.4.0: null until a driver accepts.
      'acceptedAt': null,
      if (body['scheduledAt'] == null)
        'searchStartedAt': DateTime.now().toUtc().toIso8601String(),
      'categoryId': categoryId,
      'paymentMethodId': paymentMethodId,
      // Transitional aliases keep older read-side tests compatible while every
      // new write uses the canonical backend vocabulary above.
      'rideType': categoryId,
      // openapi PaymentMethod: the method kind; the id is paymentMethodId.
      'paymentMethod': _paymentMethodKind(paymentMethodId),
      // Contract v0.3.0: Money on the wire, no whole-unit doubles, in the
      // currency of the pickup's zone (Q7). The flat `currency` sits next to
      // the flat minor fields for older readers.
      'currency': code,
      if (_bookingFareMinor(body, code) case final minor?) ...{
        'fare': _money(minor, code),
        'bookedFare': _money(minor, code),
        // ARCH-20 / contract C-4: the server owns the offer ceiling.
        'maxOfferMinor': _maxOfferMinorFor(minor, code),
      },
      // rider-9 / owner decision 5: the booked route goes through the
      // booked stops, as the booking quote priced it.
      'bookedKm': _routedKm(body),
      'stops': bookedStops,
      'bookedStops': [...bookedStops],
      'quoteId': body['quoteId'],
      'quoteSignedPayload': body['quoteSignedPayload'],
      'quoteExpiresAt': body['quoteExpiresAt'],
      'quoteTotalMinor': body['quoteTotalMinor'],
      'useWalletFirst': body['useWalletFirst'] == true,
      'walletAmountMinor': (body['walletAmountMinor'] as num?)?.round() ?? 0,
      'pickupAddress': body['pickupAddress'],
      'destinationAddress': body['destinationAddress'],
      'pickupLat': body['pickupLat'],
      'pickupLng': body['pickupLng'],
      'destinationLat': body['destinationLat'],
      'destinationLng': body['destinationLng'],
      'scheduledAt': body['scheduledAt'],
      // Rider notes are part of the ride the driver is given, so the stand-in
      // backend stores them the way the real one will.
      'notes': body['notes'],
    });
  }

  List<Map<String, dynamic>> _nearby(Map<String, dynamic>? ride) {
    final lat = (ride?['pickupLat'] as num?)?.toDouble();
    final lng = (ride?['pickupLng'] as num?)?.toDouble();
    if (lat == null || lng == null) return const [];
    return [
      {'id': 'veh_a', 'lat': lat + 0.0021, 'lng': lng - 0.0014, 'bearing': 42},
      {'id': 'veh_b', 'lat': lat - 0.0016, 'lng': lng + 0.0022, 'bearing': 210},
      {'id': 'veh_c', 'lat': lat + 0.0008, 'lng': lng + 0.0018, 'bearing': 128},
    ];
  }

  http.StreamedResponse _json(
    int status,
    Map<String, dynamic> body,
    String requestId,
  ) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      status,
      headers: {'content-type': 'application/json', 'x-request-id': requestId},
      contentLength: bytes.length,
    );
  }

  /// Q7: a booking's currency is its quote's (the pickup's zone), else the
  /// confirmed fare's, else the zone of its pickup.
  String _bookingCurrency(Map<String, dynamic> body) {
    final quote = quotes[body['quoteId']];
    final fare = body['fare'];
    return Money.normalizeCurrency(quote?['currency']) ??
        Money.normalizeCurrency(fare is Map ? fare['currency'] : null) ??
        _zoneOf(body).currency;
  }
}
