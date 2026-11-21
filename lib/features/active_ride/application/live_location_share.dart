import 'dart:async';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/maps/geo_point.dart';

export 'package:movera_rider/core/realtime/live_location_frames.dart';

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

/// Makes the [LiveLocationSender] of a trip (the screen gets this, not the
/// API client: presentation never imports the API client, guard_test).
typedef LiveLocationSenders =
    LiveLocationSender Function({
      required String tripId,
      required Duration every,
      required Future<GeoPoint?> Function() position,
      void Function(LiveShareStop why)? onStopped,
    });

/// The live senders of [api].
LiveLocationSenders liveLocationSenders(ApiClient api) =>
    ({
      required String tripId,
      required Duration every,
      required Future<GeoPoint?> Function() position,
      void Function(LiveShareStop why)? onStopped,
    }) => LiveLocationSender(
      api: api,
      tripId: tripId,
      every: every,
      position: position,
      onStopped: onStopped,
    );
