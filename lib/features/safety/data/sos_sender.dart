import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/location/location_repository.dart';

/// The phone's GPS sent once with an SOS (contract v0.7.0 `IncidentPosition`).
class SosPosition {
  const SosPosition({
    required this.lat,
    required this.lng,
    required this.at,
    this.accuracyM,
  });

  final double lat;
  final double lng;
  final double? accuracyM;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (accuracyM != null && accuracyM! >= 0) 'accuracyM': accuracyM,
    'at': at.toUtc().toIso8601String(),
  };
}

/// The phone's last position, without waiting for a new fix: an SOS goes out
/// at once. The OS's last known fix first, then the app's own last good fix;
/// null when the phone has none (the SOS is sent without a position). It
/// never waits long: after [sosLocateLimit] the SOS goes without one.
Future<SosPosition?> lastSosPosition() =>
    _lastSosPosition().timeout(sosLocateLimit, onTimeout: () => null);

/// The longest an SOS waits for the phone's position.
const sosLocateLimit = Duration(seconds: 2);

Future<SosPosition?> _lastSosPosition() async {
  try {
    final p = await Geolocator.getLastKnownPosition();
    if (p != null && p.latitude.abs() <= 90 && p.longitude.abs() <= 180) {
      return SosPosition(
        lat: p.latitude,
        lng: p.longitude,
        accuracyM: p.accuracy,
        at: p.timestamp,
      );
    }
  } catch (_) {
    // Web and plugin errors: try the app's own fix.
  }
  final saved = await const LocationRepository().readLastGoodFix();
  if (saved == null) return null;
  return SosPosition(
    lat: saved.latitude,
    lng: saved.longitude,
    at: DateTime.now().toUtc(),
  );
}

/// Contract v0.7.0 §15: `POST /rider/trips/{tripId}/sos`. One Idempotency-Key
/// per press, kept for every retry, so Movera gets one SOS however many
/// times the network drops it. The app shows only "SOS sent" afterwards.
class SosSender {
  SosSender(
    this._api, {
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final ApiClient _api;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _clock;

  /// Waits between tries when the SOS did not get through.
  static const retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// True when Movera has the SOS; false when the trip is not live (409).
  /// Throws the last error when every try failed.
  Future<bool> send(String tripId, {SosPosition? position}) async {
    final key = newIdempotencyKey('sos');
    final body = <String, dynamic>{
      'at': _clock().toUtc().toIso8601String(),
      if (position != null) 'position': position.toJson(),
    };
    final path = '/api/v1/rider/trips/${Uri.encodeComponent(tripId)}/sos';
    for (var attempt = 0; ; attempt++) {
      try {
        await _api.post(path, body: body, idempotencyKey: key);
        return true;
      } on ApiError catch (error) {
        if (error.statusCode == 409 || error.code == 'invalid_transition') {
          return false;
        }
        if (!_retryable(error) || attempt >= retryDelays.length) rethrow;
        await _sleep(retryDelays[attempt]);
      } on Exception {
        // No answer at all (the connection dropped): the same key again.
        if (attempt >= retryDelays.length) rethrow;
        await _sleep(retryDelays[attempt]);
      }
    }
  }

  static bool _retryable(ApiError error) =>
      error.code == 'NETWORK' ||
      error.code == 'TIMEOUT' ||
      error.code == 'rate_limited' ||
      error.code == 'unavailable' ||
      (error.statusCode != null && error.statusCode! >= 500);
}
