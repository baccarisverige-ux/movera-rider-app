import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:geolocator/geolocator.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/features/safety/data/pending_sos.dart';

export 'package:movera_rider/features/safety/data/pending_sos.dart';

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
///
/// Contract v0.18.148 (`sosPressTime`, owner 2026-11-20): the press is kept
/// on the phone ([PendingSosStore]) before the first try, with its press
/// time `at`. When the quick tries fail it is sent again in the background
/// with the same key and body, until Movera takes it (the server judges an
/// SOS that arrives after the trip ended by `at`), refuses it, or it is
/// [maxAge] old. A refusal or the age limit drops it and [onGivenUp] tells
/// the rider "SOS not sent, call 112" ([SosNotSentNotice]).
class SosSender {
  SosSender(
    this._api, {
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
    PendingSosStore? pending,
    this.retryInBackground = true,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now,
       _pending = pending ?? const PendingSosStore();

  final ApiClient _api;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _clock;
  final PendingSosStore _pending;

  /// False in tests that look at the quick tries alone.
  final bool retryInBackground;

  /// Waits between tries when the SOS did not get through.
  static const retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  /// The waits of the background retries (the last one repeats).
  static const backgroundDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 60),
  ];

  /// Contract v0.18.148 `sosPressTime.maxAgeSeconds` (1800): a kept SOS
  /// older than this (from its `at`) is not sent any more.
  static const maxAge = Duration(minutes: 30);

  /// Set by the app: a kept SOS was given up on (refused, too old, signed
  /// out) without reaching Movera; the rider is told.
  static void Function()? onGivenUp;

  /// Bumped by [signedOut]: a retry loop of before stops.
  static int _generation = 0;

  /// One background retry loop per signed-in rider.
  static Future<void>? _retrying;

  /// The [_generation] [_retrying] was started in: after a sign-out a new
  /// rider's SOS never joins the old rider's ending loop (review
  /// 2026-11-21).
  static int _retryingGeneration = -1;

  /// The phone storage writes, in order; the POST never waits for them.
  static Future<void> _writes = Future<void>.value();

  static void _store(Future<void> Function() write) {
    _writes = _writes.then((_) => write()).catchError((Object _) {});
  }

  @visibleForTesting
  static Future<void> get writesDone => _writes;

  @visibleForTesting
  static Future<void> resetForTesting() async {
    // Never waits: a widget test's writes may sit in its own fake clock.
    _writes = Future<void>.value();
    _retrying = null;
    onGivenUp = null;
  }

  static String _path(String tripId) =>
      '/api/v1/rider/trips/${Uri.encodeComponent(tripId)}/sos';

  /// True when Movera has the SOS; false when the trip is not live (409
  /// trip_not_live: the rider has no driver yet, "In-app SOS needs an active
  /// ride"). Throws the last error when every quick try failed; the SOS is
  /// then kept and sent again in the background.
  Future<bool> send(String tripId, {SosPosition? position}) async {
    final key = newIdempotencyKey('sos');
    final body = <String, Object?>{
      'at': _clock().toUtc().toIso8601String(),
      if (position != null) 'position': position.toJson(),
    };
    final generation = _generation;
    _store(() async {
      if (generation != _generation) return;
      await _pending.save(PendingSos(key: key, tripId: tripId, body: body));
    });
    final path = _path(tripId);
    for (var attempt = 0; ; attempt++) {
      try {
        await _api.post(path, body: body, idempotencyKey: key);
        _store(() => _pending.clear(key));
        return true;
      } on ApiError catch (error) {
        if (error.statusCode == 409 || error.code == 'invalid_transition') {
          _store(() => _pending.clear(key));
          // Any other refusal (pressed outside the trip, too old, ahead of
          // the clock) is told as "SOS not sent, call 112".
          final reason = error.reason;
          if (reason != null && reason != 'trip_not_live') onGivenUp?.call();
          return false;
        }
        if (!_keepTrying(error)) {
          _store(() => _pending.clear(key));
          onGivenUp?.call();
          rethrow;
        }
        if (attempt >= retryDelays.length) {
          _retryLater();
          rethrow;
        }
        await _sleep(retryDelays[attempt]);
      } on Exception {
        // No answer at all (the connection dropped): the same key again.
        if (attempt >= retryDelays.length) {
          _retryLater();
          rethrow;
        }
        await _sleep(retryDelays[attempt]);
      }
    }
  }

  void _retryLater() {
    if (!retryInBackground) return;
    unawaited(retryPending().catchError((Object _) {}));
  }

  /// Sends the kept SOS again (same key, same body), with growing waits,
  /// until Movera takes it, refuses it, or it is [maxAge] old. Called after
  /// a failed press and at app start; a second call while one runs joins it.
  Future<void> retryPending() {
    final running = _retrying;
    if (running != null && _retryingGeneration == _generation) return running;
    late final Future<void> loop;
    loop = _retryLoop().whenComplete(() {
      if (identical(_retrying, loop)) _retrying = null;
    });
    _retrying = loop;
    _retryingGeneration = _generation;
    return loop;
  }

  Future<void> _retryLoop() async {
    final generation = _generation;
    for (var attempt = 0; ; attempt++) {
      await _writes;
      if (generation != _generation) return;
      final sos = await _pending.read();
      if (sos == null) return;
      final at = DateTime.tryParse('${sos.body['at']}');
      if (at == null || _clock().difference(at) > maxAge) {
        await _giveUp(sos);
        return;
      }
      try {
        await _api.post(
          _path(sos.tripId),
          body: sos.body,
          idempotencyKey: sos.key,
        );
        if (generation != _generation) return;
        await _pending.clear(sos.key);
        return;
      } on ApiError catch (error) {
        if (generation != _generation) return;
        // Contract v0.18.148: any refusal (409 any reason, 404, 403, 400)
        // is final.
        if (error.statusCode == 409 || !_keepTrying(error)) {
          await _giveUp(sos);
          return;
        }
      } on Exception {
        // Network trouble: try again after the wait.
      }
      final last = backgroundDelays.length - 1;
      await _sleep(backgroundDelays[attempt < last ? attempt : last]);
    }
  }

  Future<void> _giveUp(PendingSos sos) async {
    await _pending.clear(sos.key);
    onGivenUp?.call();
  }

  /// Sign-out: the retry loop stops; a kept SOS (wiped with the rider's
  /// data) is told as not sent.
  static Future<void> signedOut({PendingSosStore? store}) async {
    _generation++;
    await _writes;
    final pending = await (store ?? const PendingSosStore()).read();
    if (pending != null) onGivenUp?.call();
  }

  /// Not given up on: a network or server trouble, or a sign-in to renew.
  static bool _keepTrying(ApiError error) =>
      _retryable(error) || error.statusCode == 401 || error.statusCode == 408;

  /// Review 2026-11-21: any 408, 429 or 5xx (also a 429 with another code
  /// or none) is retried, never taken as a refusal.
  static bool _retryable(ApiError error) =>
      error.isRetryable ||
      error.code == 'NETWORK' ||
      error.code == 'TIMEOUT' ||
      error.code == 'rate_limited' ||
      error.code == 'unavailable' ||
      (error.statusCode != null && error.statusCode! >= 500);
}
