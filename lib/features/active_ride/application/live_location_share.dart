import 'dart:async';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
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
enum LiveShareStop {
  /// `409 live_location_off`: the zone's switch is off.
  zoneOff,

  /// `409 live_location_not_active`: the ride is over (or not accepted).
  rideOver,
}

/// Sends this phone's point while the rider's "Share my location" switch is
/// on: `PUT /trips/{tripId}/live-location` every [every] (5–10 s, the
/// zone's `liveLocation.sendEverySeconds`), only while the ride screen is
/// open (the screen calls [start] / [stop]). Server CPU is the launch
/// bottleneck, so never faster; a 429 just waits for the next tick.
class LiveLocationSender {
  LiveLocationSender({
    required ApiClient api,
    required this.tripId,
    required this.position,
    this.every = const Duration(seconds: 8),
    this.onStopped,
  }) : _api = api;

  final ApiClient _api;
  final String tripId;
  final Duration every;

  /// The phone's current fix (null: none now, the tick is skipped).
  final Future<GeoPoint?> Function() position;
  final void Function(LiveShareStop why)? onStopped;

  Timer? _timer;
  bool _sending = false;

  bool get running => _timer != null;

  String get _path =>
      '/api/v1/trips/${Uri.encodeComponent(tripId)}/live-location';

  /// Sends one point now, then every [every].
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(every, (_) => unawaited(tick()));
    unawaited(tick());
  }

  /// Stops the timer and tells the other side once (`sharing: false`).
  Future<void> stop({bool tellServer = true}) async {
    final was = _timer != null;
    _timer?.cancel();
    _timer = null;
    if (!was || !tellServer) return;
    try {
      await _api.put(_path, body: {'sharing': false});
    } catch (_) {
      // The other side drops a point older than 3 × every anyway.
    }
  }

  /// One send (public for tests).
  Future<void> tick() async {
    if (_sending) return;
    _sending = true;
    try {
      final at = await position();
      if (at == null || _timer == null) return;
      await _api.put(
        _path,
        body: {'sharing': true, 'lat': at.latitude, 'lng': at.longitude},
      );
    } on ApiError catch (error) {
      final stop = switch (error.detail) {
        'live_location_off' => LiveShareStop.zoneOff,
        'live_location_not_active' => LiveShareStop.rideOver,
        _ => null,
      };
      if (stop != null) {
        await this.stop(tellServer: false);
        onStopped?.call(stop);
      }
    } catch (_) {
      // Network: the next tick tries again.
    } finally {
      _sending = false;
    }
  }
}
