import 'dart:async';

import 'package:movera_rider/core/maps/geo_point.dart';

/// Contract v0.18.144 (`contract.json#liveLocation`, owner 2026-11-20): one
/// live point of the other side of the trip, from the trip stream's
/// `event: live_location` frame (`LiveLocationEvent`, no id). Never stored:
/// it lives in memory while the ride screen is open.
class LiveLocationFrame {
  const LiveLocationFrame({
    required this.tripId,
    required this.side,
    required this.sharing,
    required this.at,
    this.point,
    this.accuracyM,
  });

  final String tripId;

  /// `rider` or `driver`: whose point it is.
  final String side;
  final bool sharing;
  final GeoPoint? point;
  final double? accuracyM;
  final DateTime at;

  /// A `LiveLocationEvent` (it has `side` and `sharing`, and no `eventId`
  /// or `sequence`, unlike a trip event), else null.
  static LiveLocationFrame? tryParse(Map<String, Object?> json) {
    if (json.containsKey('eventId') || json.containsKey('sequence')) {
      return null;
    }
    final tripId = json['tripId'];
    final side = json['side'];
    final sharing = json['sharing'];
    final at = DateTime.tryParse('${json['at']}');
    if (tripId is! String || (side != 'rider' && side != 'driver')) {
      return null;
    }
    if (sharing is! bool || at == null) return null;
    final lat = json['lat'];
    final lng = json['lng'];
    final accuracy = json['accuracyM'];
    return LiveLocationFrame(
      tripId: tripId,
      side: side as String,
      sharing: sharing,
      at: at,
      point: sharing && lat is num && lng is num
          ? GeoPoint(lat.toDouble(), lng.toDouble())
          : null,
      accuracyM: accuracy is num ? accuracy.toDouble() : null,
    );
  }
}

/// The frames the trip stream received, per trip (the stream hands them
/// here; the ride screen listens). In memory only.
abstract final class LiveLocationHub {
  static final StreamController<LiveLocationFrame> _frames =
      StreamController<LiveLocationFrame>.broadcast();

  static Stream<LiveLocationFrame> of(String tripId) =>
      _frames.stream.where((frame) => frame.tripId == tripId);

  /// True when [json] was a live frame (then it is not a trip event).
  static bool offer(Map<String, Object?> json) {
    final frame = LiveLocationFrame.tryParse(json);
    if (frame == null) return false;
    _frames.add(frame);
    return true;
  }
}

/// Why sharing stopped on the server's word.
