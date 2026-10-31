import 'package:movera_rider/core/contracts/wire_time.dart';

/// `TripProjection.eta` / a `location` event's `eta` (contract v0.18.7
/// `pickupWaiting.eta`): the ONE road-route ETA the server computes every
/// 30 s from the driver's latest fix, to the pickup until boarding and to
/// the drop-off on board. The app shows it and never computes its own.
class TripEta {
  const TripEta({
    required this.etaSeconds,
    required this.distanceMeters,
    required this.target,
    required this.at,
    required this.source,
  });

  final int etaSeconds;
  final int distanceMeters;

  /// `pickup` | `dropoff`.
  final String target;

  /// When the server computed it (server clock).
  final DateTime at;

  /// `osrm` | `estimate`.
  final String source;

  bool get toPickup => target == 'pickup';

  /// `eta.etaSeconds` as whole minutes rounded up, at least 1.
  int get minutes => minutesOf(etaSeconds);

  static int minutesOf(int seconds) {
    final minutes = (seconds / 60).ceil();
    return minutes < 1 ? 1 : minutes;
  }

  /// Parses the wire shape; null when a required field is missing.
  static TripEta? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final seconds = raw['etaSeconds'];
    final meters = raw['distanceMeters'];
    final target = raw['target'];
    final at = WireTime.tryParse(raw['at']);
    if (seconds is! num || meters is! num || target is! String || at == null) {
      return null;
    }
    final source = raw['source'];
    return TripEta(
      etaSeconds: seconds.round(),
      distanceMeters: meters.round(),
      target: target,
      at: at,
      source: source is String ? source : 'estimate',
    );
  }

  Map<String, Object?> toWire() => {
    'etaSeconds': etaSeconds,
    'distanceMeters': distanceMeters,
    'target': target,
    'at': WireTime.format(at),
    'source': source,
  };
}

/// The distance as the owner wants it shown (contract
/// `pickupWaiting.eta.distanceDisplay`, cases in
/// `fixtures/pickup_waiting.json#distanceDisplay`): kilometres with one
/// decimal from 1 km, 100 m steps under 1 km, 10 m steps under 100 m,
/// rounded DOWN so the number only shrinks as the car comes nearer, never
/// under 10 m.
class EtaDistance {
  const EtaDistance._(this.unit, this.value);

  /// `km` | `m`.
  final String unit;

  /// Kilometres with one decimal, or whole metres.
  final num value;

  static EtaDistance of(int meters) {
    if (meters >= 1000) {
      return EtaDistance._('km', (meters ~/ 100) / 10);
    }
    if (meters >= 100) return EtaDistance._('m', (meters ~/ 100) * 100);
    final tens = (meters ~/ 10) * 10;
    return EtaDistance._('m', tens < 10 ? 10 : tens);
  }

  /// The number in the app's language with its unit: sv "3,4 km", en
  /// "3.4 km", "800 m".
  String format(String languageCode) {
    if (unit == 'm') return '${value.toInt()} m';
    final text = value.toStringAsFixed(1);
    final comma = languageCode == 'sv' || languageCode == 'fr';
    return '${comma ? text.replaceFirst('.', ',') : text} km';
  }
}
