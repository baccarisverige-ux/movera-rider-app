import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/wire_time.dart';

/// Contract v0.18.9 `TripProjection.rideCheck` (owner G7 decision 1): the
/// server's "Is everything OK?", asked to the rider and the driver. Each
/// side answers for itself (`answers.rider`, `answers.driver`).
class TripRideCheck {
  const TripRideCheck({
    required this.checkId,
    required this.trigger,
    this.askedAt,
    this.answerBy,
    this.riderAnswer,
    this.alertedAt,
  });

  static const triggers = {'long_stop', 'off_route', 'dropped_far'};

  static TripRideCheck? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['checkId'];
    final trigger = raw['trigger'];
    if (id is! String || id.isEmpty || !triggers.contains(trigger)) {
      return null;
    }
    final answers = raw['answers'];
    final rider = answers is Map ? answers['rider'] : null;
    return TripRideCheck(
      checkId: id,
      trigger: trigger as String,
      askedAt: WireTime.tryParse(raw['askedAt']),
      answerBy: WireTime.tryParse(raw['answerBy']),
      riderAnswer: rider is String ? rider : null,
      alertedAt: WireTime.tryParse(raw['alertedAt']),
    );
  }

  final String checkId;

  /// `long_stop`, `off_route` or `dropped_far`.
  final String trigger;
  final DateTime? askedAt;
  final DateTime? answerBy;
  final String? riderAnswer;
  final DateTime? alertedAt;

  /// True while the rider still has to answer (before `answerBy`).
  bool openForRider(DateTime now) =>
      riderAnswer == null && (answerBy == null || now.isBefore(answerBy!));
}

/// A place of a route change (`{lat, lng, address?}`).
class TripChangePlace {
  const TripChangePlace({required this.lat, required this.lng, this.address});

  static TripChangePlace? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    if (lat is! num || lng is! num) return null;
    final address = raw['address'];
    return TripChangePlace(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      address: address is String && address.trim().isNotEmpty
          ? address.trim()
          : null,
    );
  }

  final double lat;
  final double lng;
  final String? address;

  Map<String, Object?> toWire() => {
    'lat': lat,
    'lng': lng,
    if (address != null) 'address': address,
  };
}

/// Contract v0.18.9 `TripProjection.routeChange` (owner G7 decision 3): the
/// rider's new drop-off / stops while the driver answers. Refused, expired
/// or withdrawn keeps the old route.
class TripRouteChange {
  const TripRouteChange({
    required this.changeId,
    required this.status,
    this.dropoff,
    this.stops = const [],
    this.total,
    this.difference,
    this.answerBy,
    this.answeredBy,
  });

  static const statuses = {
    'pending',
    'accepted',
    'refused',
    'expired',
    'withdrawn',
  };

  static TripRouteChange? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['changeId'];
    final status = raw['status'];
    if (id is! String || id.isEmpty || !statuses.contains(status)) {
      return null;
    }
    final stops = raw['stops'];
    final by = raw['answeredBy'];
    return TripRouteChange(
      changeId: id,
      status: status as String,
      dropoff: TripChangePlace.fromWire(raw['dropoff']),
      stops: [
        if (stops is List)
          for (final stop in stops) ?TripChangePlace.fromWire(stop),
      ],
      total: Money.fromWire(raw['total']),
      difference: Money.fromWire(raw['difference']),
      answerBy: WireTime.tryParse(raw['answerBy']),
      answeredBy: by is String ? by : null,
    );
  }

  final String changeId;
  final String status;
  final TripChangePlace? dropoff;
  final List<TripChangePlace> stops;
  final Money? total;
  final Money? difference;
  final DateTime? answerBy;
  final String? answeredBy;

  bool get pending => status == 'pending';
  bool get accepted => status == 'accepted';

  /// Refused, expired or withdrawn: the old route stays.
  bool get kept => !pending && !accepted;
}
