part of 'in_process_mock_client.dart';

/// Demo-only places around Södertälje and Stockholm (and a few in Paris
/// and Tunis), so address search can be tried on GitHub Pages. The live
/// API searches real addresses.
const List<(String, String, double, double)> _demoPlaces = [
  ('Klockarvägen 37', '151 59 Södertälje', 59.1955, 17.6253),
  ('Klockarvägen 98', 'Södertälje', 59.1949, 17.6301),
  ('Klockarvägen 104', 'Södertälje', 59.1946, 17.6318),
  ('Klockarvägen 110', 'Södertälje', 59.1941, 17.6336),
  ('Klostergatan 3', 'Södertälje', 59.1991, 17.6262),
  ('Albyvägen 5', '145 59 Norsborg', 59.2448, 17.8562),
  ('Alby Centrum', 'Albyvägen 6, Norsborg', 59.2393, 17.8457),
  ('Drottninggatan 5', '111 51 Stockholm', 59.3326, 18.0649),
  ('Drottninggatan 5', '753 10 Uppsala', 59.8586, 17.6389),
  ('Stockholm Central', 'Centralplan 15, Stockholm', 59.3303, 18.0590),
  ('Stockholm Arlanda Airport', 'Arlanda', 59.6498, 17.9238),
  ('Arlanda Airport Terminal 5', 'Arlanda', 59.6519, 17.9297),
  ('Södertälje Centrum', 'Storgatan, Södertälje', 59.1960, 17.6260),
  ('Svarvarvägen 5', '142 50 Stockholm', 59.2089, 17.9466),
  ('Mall of Scandinavia', 'Stjärntorget 2, Solna', 59.3700, 18.0050),
  // Q7: places in the Paris Centre and Tunis Centre zones, so a demo trip
  // can be priced in euros or dinars.
  ('Gare du Nord', '18 Rue de Dunkerque, Paris', 48.8809, 2.3553),
  ('Musée du Louvre', 'Rue de Rivoli, Paris', 48.8606, 2.3376),
  ('Avenue Habib Bourguiba', 'Tunis', 36.8008, 10.1865),
  ('Médina de Tunis', 'Tunis', 36.7983, 10.1700),
];

String _fold(String value) {
  const from = 'åäöéèêëàâüïîôç';
  const to = 'aaoeeeeaauiioc';
  final out = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    final i = from.indexOf(char);
    out.write(i < 0 ? char : to[i]);
  }
  return out.toString();
}

/// The stored trip status. Stored rides carry a contract name; a legacy
/// Rider name (tests that seed `rides[...]` by hand) is read through the
/// UI → trip map once, then the trip is written back in contract form.
TripStatus _statusOf(Map<String, dynamic> ride) {
  final raw = ride['status'];
  final trip = TripStatusWire.parse(raw);
  if (trip != null) return trip;
  final legacy = RideStatusWire.legacyName(raw);
  return legacy?.tripStatus ?? TripStatus.draft;
}

TripKind _kindOf(Map<String, dynamic> ride) =>
    TripKindWire.parse(ride['kind']) ??
    (ride['scheduledAt'] != null ? TripKind.scheduled : TripKind.live);

/// One committed change: version + 1, new updatedAt, and the next
/// server-assigned realtime `sequence` with a unique `eventId` and its
/// event kind (contract v0.3.0 §4; clients never number events).
void _touch(Map<String, dynamic> ride, [String eventKind = 'trip_projection']) {
  ride['version'] = ((ride['version'] as num?)?.toInt() ?? 0) + 1;
  ride['updatedAt'] = DateTime.now().toUtc().toIso8601String();
  _sequenceEvent(ride, eventKind);
}

void _sequenceEvent(Map<String, dynamic> ride, String eventKind) {
  final sequence = ((ride['sequence'] as num?)?.toInt() ?? 0) + 1;
  final id = (ride['tripId'] ?? ride['id']).toString();
  ride['sequence'] = sequence;
  ride['eventId'] = 'ev_${id}_$sequence';
  ride['eventKind'] = eventKind;
}

/// `409 version_mismatch` with the projection when [body] carries an
/// `expectedVersion` that is not the trip's current version (contract §1
/// Concurrency). Null when it matches or is absent (pre-v0.3 clients).
Map<String, dynamic>? _versionMismatch(
  Map<String, dynamic> ride,
  Map<String, dynamic> body,
  String requestId,
) {
  final expected = body['expectedVersion'];
  if (expected == null) return null;
  final current = (ride['version'] as num?)?.toInt() ?? 0;
  if (expected is int && expected == current) return null;
  return {
    'code': 'version_mismatch',
    'message': 'The trip is at version $current, not $expected.',
    'requestId': requestId,
    'retryable': false,
    'projection': ride,
    'ride': ride,
  };
}

/// Whether [code] is a reason [actor] may give for [command]
/// (`contract.json#cancelReasons`, by actor group).
bool _reasonAllowed(Object? code, String command, TripActor actor) {
  if (code is! String) return false;
  final groups = switch ((actor, command)) {
    (TripActor.rider, 'cancel' || 'end_early') => [CancelReasonCodes.rider],
    (TripActor.driver, 'no_show') => [CancelReasonCodes.noShow],
    (TripActor.driver, 'cancel') => [
      _driverBeforeTrip,
      _driverDuringTrip,
      _driverNextTrip,
      _driverScheduled,
    ],
    (TripActor.admin, _) => [CancelReasonCodes.admin],
    (TripActor.system, _) => [CancelReasonCodes.system],
    _ => const <List<String>>[],
  };
  return groups.any((group) => group.contains(code));
}

const _driverBeforeTrip = [
  'rider_requested_cancel',
  'rider_not_at_pickup',
  'unsafe_pickup',
  'vehicle_issue_before_start',
  'driver_emergency_before_start',
  'other_before_start',
];
const _driverDuringTrip = [
  'rider_requested_early_end',
  'safety_concern_on_trip',
  'vehicle_issue_on_trip',
  'accident_or_road_emergency',
  'rider_behavior',
  'trip_or_destination_issue',
  'other_on_trip',
];
const _driverNextTrip = [
  'next_trip_current_running_late',
  'next_trip_pickup_too_far',
  'next_trip_rider_requested',
  'next_trip_vehicle_issue',
  'next_trip_driver_emergency',
  'next_trip_other',
];
const _driverScheduled = [
  'scheduled_cannot_make_time',
  'scheduled_vehicle_issue',
  'scheduled_personal_emergency',
  'scheduled_pickup_too_far',
  'scheduled_trip_details',
  'scheduled_other',
];

/// Contract error body (`contract.json#errors`): `{code, message,
/// requestId, retryable, projection?}` with a lower-case contract [code]
/// (R-O4). [reason] is this stand-in's more specific cause in lower case
/// (`otp_expired`, `pickup_locked`, …) beside it, not a contract field;
/// clients fall back to [code] when a server sends none. `ride` is kept
/// as the pre-v0.3 alias of `projection`.
Map<String, dynamic> _error(
  String code,
  String requestId, {
  String? reason,
  String? message,
  Map<String, dynamic>? projection,
}) => {
  'code': code,
  'reason': ?reason,
  'message': message ?? reason ?? code,
  'requestId': requestId,
  'retryable':
      code == 'internal' || code == 'unavailable' || code == 'rate_limited',
  'projection': ?projection,
  'ride': ?projection,
};

/// A refused route change: a stage that no longer allows it is
/// `invalid_transition`, a missing destination `invalid_request`, a
/// route quote that no longer matches `conflict`; with the projection.
Map<String, dynamic> _routeChangeError(
  String reason,
  Map<String, dynamic> ride,
  String requestId,
) => _error(
  switch (reason) {
    'ride_finished' || 'pickup_locked' => 'invalid_transition',
    'destination_required' || 'pickup_too_far' => 'invalid_request',
    _ => 'conflict',
  },
  requestId,
  reason: reason,
  projection: ride,
);

Map<String, dynamic> _invalidReason(
  Object? code,
  TripActor actor,
  String requestId,
) => {
  'code': 'invalid_request',
  'message': '$code is not a ${actor.wireName} cancel reason.',
  'requestId': requestId,
  'retryable': false,
};

/// `409 invalid_transition` (contract errors shape) with the projection.
/// `ride` is kept as the pre-v0.3 alias of `projection`.
Map<String, dynamic> _invalidTransition(
  Map<String, dynamic> ride,
  String command,
  String requestId,
) => {
  'code': 'invalid_transition',
  'message':
      '$command is not allowed while the trip is ${_statusOf(ride).wireName}.',
  'requestId': requestId,
  'retryable': false,
  'projection': ride,
  'ride': ride,
};

/// The payment statuses between [from] (null: no payment yet, which may
/// start at `pending`) and [to] along `paymentTransitions`, or null.
List<TripPaymentStatus>? _paymentWalk(
  TripPaymentStatus? from,
  TripPaymentStatus to,
) {
  if (from == to) return const [];
  final start = from ?? TripPaymentStatus.pending;
  if (start == to) return [to];
  final previous = <TripPaymentStatus, TripPaymentStatus>{};
  final queue = [start];
  while (queue.isNotEmpty) {
    final at = queue.removeAt(0);
    for (final next
        in tripPaymentTransitions[at] ?? const <TripPaymentStatus>{}) {
      if (next == start || previous.containsKey(next)) continue;
      previous[next] = at;
      if (next == to) {
        final walk = <TripPaymentStatus>[to];
        var back = at;
        while (back != start) {
          walk.insert(0, back);
          back = previous[back]!;
        }
        return walk;
      }
      queue.add(next);
    }
  }
  return null;
}

/// ARCH-20: true when [increaseMinor] would take the fare over the
/// ceiling.
bool _offerAboveMaximum(Map<String, dynamic> ride, int? increaseMinor) {
  final max = ride['maxOfferMinor'];
  final fare = _fareMinor(ride);
  if (increaseMinor == null || max is! num || fare == null) return false;
  return fare + increaseMinor > max;
}

extension _MockTrips on InProcessMockClient {
  void _evictIdempotency() {
    final cutoff = _clock().subtract(InProcessMockClient.idempotencyTtl);
    idempotency.removeWhere((_, replay) => replay.at.isBefore(cutoff));
    while (idempotency.length > InProcessMockClient.idempotencyLimit) {
      idempotency.remove(idempotency.keys.first);
    }
  }

  List<Map<String, dynamic>> _demoSuggestions(
    String query, {
    bool typedFallback = true,
  }) {
    final words = _fold(query.trim()).split(RegExp(r'[\s,]+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const [];
    final found = <Map<String, dynamic>>[];
    for (final (title, subtitle, lat, lng) in _demoPlaces) {
      final hay = _fold('$title $subtitle');
      final tokens = hay.split(RegExp(r'[\s,]+'));
      final all = words.every(
        (w) => tokens.any((t) => t.startsWith(w)) || hay.contains(w),
      );
      if (!all) continue;
      found.add({
        'title': title,
        'subtitle': subtitle,
        'latitude': lat,
        'longitude': lng,
      });
    }
    // Anything else typed is still offered, so demo bookings always work.
    final typed = query.trim();
    if (typedFallback && typed.length >= 3 && found.isEmpty) {
      final hash = _fold(typed).codeUnits.fold<int>(
        0,
        (value, unit) => ((value * 31) + unit) & 0x7fffffff,
      );
      found.add({
        'title': typed,
        'subtitle': 'Sweden',
        'latitude': 59.3293 + (((hash % 1201) - 600) / 100000.0),
        'longitude': 18.0686 + ((((hash ~/ 1201) % 1601) - 800) / 100000.0),
      });
    }
    return found.take(8).toList();
  }

  void _expireSearchIfDue(Map<String, dynamic> ride) {
    final current = _statusOf(ride);
    if (current != TripStatus.searching && current != TripStatus.offered) {
      return;
    }
    final startedRaw = ride['searchStartedAt'];
    final started = startedRaw is String ? DateTime.tryParse(startedRaw) : null;
    if (started == null) return;
    final now = DateTime.now().toUtc();
    if (now.difference(started) < searchExpiresAfter) return;
    // `expire` (system): no driver found in time.
    _apply(ride, 'expire', TripActor.system);
  }

  /// Applies [command] by [actor] through [TripStateMachine]. False (and
  /// nothing changed) when the table does not allow it.
  bool _apply(Map<String, dynamic> ride, String command, TripActor actor) {
    final from = _statusOf(ride);
    final to = TripStateMachine.apply(
      from,
      command,
      actor,
      kind: _kindOf(ride),
    );
    if (to == null) return false;
    ride['status'] = to.wireName;
    final tripId = (ride['tripId'] ?? ride['id']).toString();
    if (to == TripStatus.accepted) {
      final at = _clock();
      _acceptedAt[tripId] = at;
      _acceptedPickup.remove(tripId);
      // Contract v0.4.0 `TripProjection.acceptedAt` (Q12): the rider's
      // free-cancel clock counts from it.
      ride['acceptedAt'] = WireTime.format(at);
    } else if (to == TripStatus.searching || to == TripStatus.requested) {
      // Back in dispatch: the next accept starts a new free window.
      _acceptedAt.remove(tripId);
      _acceptedPickup.remove(tripId);
      ride['acceptedAt'] = null;
      ride.remove('waiting');
    }
    if (to == TripStatus.arrived) {
      // `TripProjection.waiting` (Q41/Q42): the waiting clock starts at
      // arrival; the category's free wait comes from the zone config.
      final at = _clock();
      final terms = _configFor(_currencyOf(ride)).waiting?.forCategory(
        (ride['categoryId'] ?? ride['rideType'] ?? '').toString(),
      );
      final freeUntil = at.add(Duration(minutes: terms?.freeWaitMin ?? 5));
      ride['waiting'] = {
        'arrivedAt': WireTime.format(at),
        'freeUntil': WireTime.format(freeUntil),
        'noShowAt': WireTime.format(
          at.add(Duration(minutes: terms?.noShowAfterMin ?? 5)),
        ),
        'chargedSeconds': 0,
      };
    }
    if (to == TripStatus.searching && from != TripStatus.offered) {
      // Back in dispatch (driver drop / admin reassign): the old driver is
      // gone and the search clock restarts.
      ride
        ..remove('driver')
        ..remove('driverLat')
        ..remove('driverLng');
      ride['searchStartedAt'] = DateTime.now().toUtc().toIso8601String();
    }
    if (to == TripStatus.completed) {
      // Payment and rating start as fields once the trip is done.
      ride['ratingStatus'] = TripRatingStatus.notRequested.wireName;
    }
    if (actor != TripActor.rider &&
        to.isTerminal &&
        to != TripStatus.completed) {
      ride['cancellation'] ??= {
        'actor': actor.wireName,
        // openapi Cancellation requires a code of the actor's group.
        'reasonCode': switch ((actor, command)) {
          (_, 'no_show') => 'rider_no_show',
          (TripActor.driver, _) => 'other_on_trip',
          (TripActor.admin, _) => 'admin_other',
          (_, 'expire') => 'system_no_driver',
          _ => 'system_error',
        },
        'at': DateTime.now().toUtc().toIso8601String(),
        'fee': null,
      };
    }
    _touch(ride, switch ((actor, command)) {
      (TripActor.rider, 'cancel' || 'end_early') => 'rider_cancelled',
      (TripActor.driver, 'cancel') => 'driver_cancelled',
      _ => 'trip_projection',
    });
    return true;
  }

  /// `contract.json#ratingAllowed`: the rider rates a completed trip and
  /// one they ended early (R-O6), never a plain cancel.
  bool _rateable(Map<String, dynamic> ride, String tripId) {
    final status = _statusOf(ride);
    return TripRatingRules.allows(
      TripActor.rider,
      status,
      endedBy: _endedEarly.contains(tripId) ? 'end_early' : null,
    );
  }

  /// R-O1: adds the stretch from the last on-board fix to ([lat], [lng]).
  /// The first fix after boarding only marks where driving started.
  void _trackDriven(Map<String, dynamic> ride, Object? lat, Object? lng) {
    if (lat is! num || lng is! num) return;
    if (!tripRiderOnboardStatuses.contains(_statusOf(ride))) return;
    final tripId = (ride['tripId'] ?? ride['id']).toString();
    final last = _driven[tripId];
    final meters = last == null
        ? 0.0
        : last.meters + _km(last.lat, last.lng, lat, lng) * 1000;
    _driven[tripId] = (
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      meters: meters,
    );
  }

  /// R-O1 (owner decision): what an ended-early trip costs. The rider pays
  /// for the distance driven at the category's own rates, the ones the
  /// quote engine below prices with ([MockCategoryRates]): base fare + km
  /// driven × per-km rate, in the currency's minor units. Never more than
  /// the trip's current fare. Null when the trip has no fare.
  ({Money fare, Money base, Money distance})? _endEarlyFare(
    Map<String, dynamic> ride,
  ) {
    final currentMinor = _fareMinor(ride);
    if (currentMinor == null) return null;
    final category = CategoryIds.canonical(
      (ride['categoryId'] ?? ride['rideType'] ?? '').toString(),
    );
    // Q7: in the trip's own currency, at the zone's rates.
    final code = _currencyOf(ride);
    final rates = _ratesFor(category, code);
    final tripId = (ride['tripId'] ?? ride['id']).toString();
    final meters = drivenMetersOf(tripId);
    final base = rates.baseFare;
    final distance = rates.distanceFare(meters);
    final total = base.amountMinor + distance.amountMinor;
    if (total <= currentMinor) {
      return (fare: Money(total, code), base: base, distance: distance);
    }
    // Capped at the agreed fare: ending early never costs more than the
    // whole trip (a detour, a promotion or a lower offer).
    final cappedDistance = math.max(0, currentMinor - base.amountMinor);
    return (
      fare: Money(currentMinor, code),
      base: Money(currentMinor - cappedDistance, code),
      distance: Money(cappedDistance, code),
    );
  }

  /// What a rider cancel costs now (contract §6 FeeRule, the shared
  /// calculator): live trips from the category's live rule, counted from
  /// the driver's accept (free before one accepted); scheduled trips from
  /// the reservation rule, counted to pickup (free once pickup passed with
  /// no driver). Null when free.
  Money? _riderCancelFee(Map<String, dynamic> ride) {
    final fareMinor = _fareMinor(ride);
    if (fareMinor == null) return null;
    // Q7: the fee rule of the trip's own zone, in its currency.
    final code = _currencyOf(ride);
    final config = _configFor(code);
    final fare = Money(fareMinor, code);
    final category = CategoryIds.canonical(
      (ride['categoryId'] ?? ride['rideType'] ?? '').toString(),
    );
    final now = _clock();
    Money? fee;
    if (_kindOf(ride) == TripKind.scheduled) {
      final rule = config.reservationFeeFor(category);
      final pickup = WireTime.tryParse(ride['scheduledAt']);
      if (rule == null || pickup == null) return null;
      if (ride['driver'] == null && !now.isBefore(pickup)) return null;
      fee = CancelFeeCalculator.reservation(
        rule,
        fare,
        pickup.difference(now).inMinutes,
      );
    } else {
      final rule = config.liveFeeFor(category);
      final accepted = _acceptedAt[(ride['tripId'] ?? ride['id']).toString()];
      if (rule == null || accepted == null) return null;
      fee = CancelFeeCalculator.live(
        rule,
        fare,
        now.difference(accepted).inMinutes,
      );
    }
    return fee.isPositive ? fee : null;
  }

  /// The demo simulator (see the `/status` route). Returns the refused
  /// command, or null when everything asked for was applied.
  String? _simulate(Map<String, dynamic> ride, Map<String, dynamic> body) {
    final command = body['command'];
    if (command is String) {
      final actor = TripActorWire.parse(body['actor']) ?? TripActor.driver;
      return _apply(ride, command, actor) ? null : command;
    }

    TripStatus? target;
    TripPaymentStatus? payment = TripPaymentStatusWire.parse(
      body['paymentStatus'],
    );
    TripRatingStatus? rating = TripRatingStatusWire.parse(body['ratingStatus']);
    final rawStatus = body['status'];
    if (rawStatus != null) {
      target = TripStatusWire.parse(rawStatus);
      final legacy = target == null
          ? RideStatusWire.legacyName(rawStatus)
          : null;
      if (legacy != null) {
        target = legacy.tripStatus;
        // Pre-v0.3 post-trip "statuses" are payment/rating fields now.
        switch (legacy) {
          case RideStatus.paymentProcessing:
            payment ??= TripPaymentStatus.authorized;
          case RideStatus.paymentFinalized:
            payment ??= TripPaymentStatus.captured;
          case RideStatus.ratingPending:
            payment ??= TripPaymentStatus.captured;
            rating ??= TripRatingStatus.pending;
          case RideStatus.closed:
            payment ??= TripPaymentStatus.captured;
            rating ??= TripRatingStatus.skipped;
          case RideStatus.paymentFailed:
            payment ??= TripPaymentStatus.failed;
          default:
            break;
        }
      }
      if (target == null) return 'status';
    }

    if (target != null && target != _statusOf(ride)) {
      final kind = _kindOf(ride);
      final path =
          TripStateMachine.pathTo(_statusOf(ride), target, kind: kind) ??
          TripStateMachine.pathTo(
            _statusOf(ride),
            target,
            kind: kind,
            actors: TripActor.values.toSet(),
          );
      if (path == null) return 'status:${target.wireName}';
      for (final (step, actor) in path) {
        if (!_apply(ride, step, actor)) return step;
      }
    }

    if (payment != null || rating != null) {
      if (_statusOf(ride) != TripStatus.completed) return 'settle';
      if (payment != null) {
        final current = TripPaymentStatusWire.parse(ride['paymentStatus']);
        final walk = _paymentWalk(current, payment);
        if (walk == null) return 'payment:${payment.wireName}';
        if (walk.isNotEmpty) {
          ride['paymentStatus'] = payment.wireName;
          _touch(ride, 'payment_updated');
        }
      }
      if (rating != null) {
        final current =
            TripRatingStatusWire.parse(ride['ratingStatus']) ??
            TripRatingStatus.notRequested;
        if (current != rating) {
          final allowed =
              tripRatingTransitions[current]?.contains(rating) ?? false;
          final viaPending =
              current == TripRatingStatus.notRequested &&
              rating != TripRatingStatus.pending;
          if (!allowed && !viaPending) return 'rating:${rating.wireName}';
          ride['ratingStatus'] = rating.wireName;
          _touch(ride, 'rating_updated');
        }
      }
    }
    return null;
  }

  /// How far (metres) [body] moves the trip's pickup from the pickup the
  /// driver accepted (rider-u13), when both ends are known. Only called
  /// while the trip is accepted or the driver is on the way.
  double? _pickupMoveMeters(
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final toLat = body['pickupLat'];
    final toLng = body['pickupLng'];
    final id = (ride['tripId'] ?? ride['id']).toString();
    var from = _acceptedPickup[id];
    if (from == null) {
      final lat = ride['pickupLat'];
      final lng = ride['pickupLng'];
      if (lat is! num || lng is! num) return null;
      from = _acceptedPickup[id] = (lat: lat.toDouble(), lng: lng.toDouble());
    }
    if (toLat is! num || toLng is! num) return null;
    return GeoDistance.metersBetween(
      from.lat,
      from.lng,
      toLat.toDouble(),
      toLng.toDouble(),
    );
  }

  /// Pickup can move until the driver is at the door; the destination and
  /// the stops can change until the trip is over.
  String? _routeChangeDenied(
    Map<String, dynamic> ride,
    Map<String, dynamic> body,
  ) {
    final current = _statusOf(ride);
    if (current.isTerminal) return 'ride_finished';
    final pickupChanged =
        body['pickupAddress'] != null &&
        body['pickupAddress'] != ride['pickupAddress'];
    const pickupEditable = {
      TripStatus.requested,
      TripStatus.searching,
      TripStatus.offered,
      TripStatus.accepted,
      TripStatus.driverToPickup,
    };
    if (pickupChanged && !pickupEditable.contains(current)) {
      return 'pickup_locked';
    }
    // Q40: once a driver has accepted, the pickup moves only a short way.
    final moved =
        pickupChanged &&
            (current == TripStatus.accepted ||
                current == TripStatus.driverToPickup)
        ? _pickupMoveMeters(ride, body)
        : null;
    if (moved != null &&
        moved > _configFor(_currencyOf(ride)).maxPickupMoveMeters) {
      return 'pickup_too_far';
    }
    if (body['destinationLat'] is! num || body['destinationLng'] is! num) {
      return 'destination_required';
    }
    return null;
  }

  /// The highest fare a rider may offer for a ride priced [fareMinor] in
  /// [code]: the zone's `raisePrice.maxFactor` (contract v0.18.6, owner
  /// G4-E4, default 2×), in whole major units (kronor, euros, dinars),
  /// rounded down so it never passes the limit.
  int _maxOfferMinorFor(int fareMinor, String code) {
    final unit = Money.minorPerMajor(code);
    final ceiling = RaiseLimit.ceilingMinor(
      fareMinor,
      _configFor(code).raiseMaxFactor,
    );
    return (ceiling ~/ unit) * unit;
  }
}
