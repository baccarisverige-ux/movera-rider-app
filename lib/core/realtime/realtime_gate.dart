/// Disposition of one realtime event at the gate (`fixtures/events.json`).
enum RealtimeDisposition {
  accepted,
  acceptedWithGap,
  duplicate,
  blockedAfterTerminal,
  invalid,
}

extension RealtimeDispositionWire on RealtimeDisposition {
  String get wireName => switch (this) {
    RealtimeDisposition.accepted => 'accepted',
    RealtimeDisposition.acceptedWithGap => 'accepted_with_gap',
    RealtimeDisposition.duplicate => 'duplicate',
    RealtimeDisposition.blockedAfterTerminal => 'blocked_after_terminal',
    RealtimeDisposition.invalid => 'invalid',
  };

  /// The event is applied (a gap also asks for a resync).
  bool get passes =>
      this == RealtimeDisposition.accepted ||
      this == RealtimeDisposition.acceptedWithGap;
}

/// `contract.json#realtime.kinds`.
enum RealtimeKind {
  tripProjection,
  riderCancelled,
  driverCancelled,
  location,
  driverArrived,
  riderOnTheWay,
  paymentUpdated,
  ratingUpdated,
  message,

  /// v0.18.7: the rider moved the pickup (carries the projection).
  pickupMoved,
}

extension RealtimeKindWire on RealtimeKind {
  String get wireName => switch (this) {
    RealtimeKind.tripProjection => 'trip_projection',
    RealtimeKind.riderCancelled => 'rider_cancelled',
    RealtimeKind.driverCancelled => 'driver_cancelled',
    RealtimeKind.location => 'location',
    RealtimeKind.driverArrived => 'driver_arrived',
    RealtimeKind.riderOnTheWay => 'rider_on_the_way',
    RealtimeKind.paymentUpdated => 'payment_updated',
    RealtimeKind.ratingUpdated => 'rating_updated',
    RealtimeKind.message => 'message',
    RealtimeKind.pickupMoved => 'pickup_moved',
  };

  /// `contract.json#realtime.afterTerminal`.
  bool get passesAfterTerminal =>
      this == RealtimeKind.paymentUpdated ||
      this == RealtimeKind.ratingUpdated ||
      this == RealtimeKind.message;

  static RealtimeKind? parse(Object? raw) {
    if (raw is! String) return null;
    for (final kind in RealtimeKind.values) {
      if (kind.wireName == raw.trim()) return kind;
    }
    return null;
  }
}

/// The realtime gate every app runs (`contract.json#realtime.rules`,
/// cases in `fixtures/events.json`), for one trip stream.
///
/// - invalid: `sequence < 1` or a blank `tripId`;
/// - duplicate: an `eventId` already seen, or `sequence <= last`;
/// - blocked after terminal: once a terminal lifecycle status was accepted,
///   only `payment_updated`, `rating_updated` and `message` pass (a blocked
///   event still moves the cursor);
/// - accepted with gap: `sequence > last + 1` (accept, then resync).
///
/// The sequence is always the server's; this gate never numbers events.
class RealtimeGate {
  RealtimeGate({this.memory = 256});

  /// How many event ids are remembered for dedupe.
  final int memory;

  int _last = 0;
  bool _terminal = false;
  final List<String> _order = [];
  final Set<String> _seen = {};

  int get lastSequence => _last;
  bool get sawTerminal => _terminal;

  /// Decides [eventId] at [sequence]. [isTerminalStatus] tells whether the
  /// event carries a terminal lifecycle status (projection.status).
  RealtimeDisposition admit({
    required String eventId,
    required String tripId,
    required int sequence,
    required RealtimeKind kind,
    bool isTerminalStatus = false,
  }) {
    if (sequence < 1 || tripId.trim().isEmpty) {
      return RealtimeDisposition.invalid;
    }
    if (_seen.contains(eventId) || sequence <= _last) {
      return RealtimeDisposition.duplicate;
    }
    if (_terminal && !kind.passesAfterTerminal) {
      _remember(eventId, sequence);
      return RealtimeDisposition.blockedAfterTerminal;
    }
    final gap = _last > 0 && sequence > _last + 1;
    _remember(eventId, sequence);
    if (isTerminalStatus) _terminal = true;
    return gap
        ? RealtimeDisposition.acceptedWithGap
        : RealtimeDisposition.accepted;
  }

  void _remember(String eventId, int sequence) {
    _last = sequence;
    if (_seen.add(eventId)) {
      _order.add(eventId);
      if (_order.length > memory) _seen.remove(_order.removeAt(0));
    }
  }

  /// Forget everything (a different trip on the same stream owner).
  void reset() {
    _last = 0;
    _terminal = false;
    _order.clear();
    _seen.clear();
  }
}
