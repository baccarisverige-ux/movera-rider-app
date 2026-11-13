import 'dart:async';
import 'dart:math' as math;

import 'package:movera_rider/core/contracts/trip_transitions.dart';

import 'check_log.dart';
import 'movera_api.dart';

/// The DRIVER of the rider device run (G31 rider, owner 2026-11-12: "then
/// the RIDER app on phone (driver via API) with the same checks"), played
/// over HTTP with the shared big-test driver (se.d38, the driver suite's
/// pair of se.r35) handed over at run time.
///
/// Its position is HTTP fixes (`POST /driver/location` every
/// [feedEvery], a plain [Timer]: no pump), not the phone's mock GPS (that
/// stays at the rider's pickup). Never prints a number, a code or a token.
class DriverPeer {
  DriverPeer(Uri base)
    : api = DriverApi(
        base,
        // The driver app sends it; without it the server skips the pickup
        // PIN and the arrive position check (contract 0.18.14).
        contractVersion: TripStateMachine.contractVersion,
      );

  final DriverApi api;

  static const Duration feedEvery = Duration(seconds: 3);

  double lat = 0;
  double lng = 0;
  double speedMps = 0;
  double? heading;

  /// The trip the fixes are sent for (null before the accept).
  String? tripId;

  Timer? _feeder;
  bool _sending = false;
  int fixesSent = 0;
  int fixesFailed = 0;
  String? lastFixAnswer;

  bool online = false;

  /// The driver's profile as last read (categoryIds, version, status).
  Map<String, dynamic>? profile;

  Set<String> get categoryIds => <String>{
    if (profile?['categoryIds'] is List)
      ...(profile!['categoryIds'] as List).whereType<String>(),
  };

  String? get onlineStatus => profile?['onlineStatus'] as String?;

  Future<String?> signIn({required String phone, required String code}) =>
      api.signIn(phone: phone, code: code, app: 'driver');

  Future<ApiAnswer> readProfile() async {
    final answer = await api.profile();
    if (answer.ok) profile = answer.map;
    return answer;
  }

  /// Online at ([atLat], [atLng]); the feeder starts. Returns null when
  /// the server says online, else why not.
  Future<String?> goOnline(double atLat, double atLng) async {
    lat = atLat;
    lng = atLng;
    final read = await readProfile();
    if (!read.ok) return 'profile ${read.short}';
    final version = profile?['version'];
    if (version is! num) return 'profile has no version';
    if (onlineStatus != 'online' && onlineStatus != 'on_trip') {
      final asked = await api.availability(
        version.toInt(),
        'online',
        location: geoFix(lat, lng),
      );
      if (!asked.ok) return 'availability online ${asked.short}';
    }
    startFeeder();
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(end)) {
      await readProfile();
      if (onlineStatus == 'online' || onlineStatus == 'on_trip') {
        online = true;
        return null;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return 'server says ${onlineStatus ?? 'unknown'} after 30 s';
  }

  void startFeeder() {
    _feeder ??= Timer.periodic(feedEvery, (_) => unawaited(_feed()));
    unawaited(_feed());
  }

  void stopFeeder() {
    _feeder?.cancel();
    _feeder = null;
  }

  Future<void> _feed() async {
    if (_sending) return;
    _sending = true;
    try {
      final answer = await api.sendFixes([
        geoFix(lat, lng, speedMps: speedMps, heading: heading),
      ], tripId: tripId);
      lastFixAnswer = answer.short;
      answer.ok ? fixesSent++ : fixesFailed++;
    } finally {
      _sending = false;
    }
  }

  /// Drives in a straight line to ([toLat], [toLng]) at [metersPerSecond],
  /// one position a second ([pause] lets that second pass on the phone),
  /// then stands still there.
  Future<void> driveTo(
    double toLat,
    double toLng,
    Future<void> Function(Duration) pause, {
    double metersPerSecond = 10,
  }) async {
    final meters = distanceMeters(lat, lng, toLat, toLng);
    final steps = math.max(1, (meters / metersPerSecond).ceil());
    final fromLat = lat, fromLng = lng;
    heading = _bearing(fromLat, fromLng, toLat, toLng);
    speedMps = metersPerSecond;
    CheckLog.say('STEP driver peer drives ${meters.round()} m in $steps s');
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      lat = fromLat + (toLat - fromLat) * t;
      lng = fromLng + (toLng - fromLng) * t;
      await pause(const Duration(seconds: 1));
    }
    speedMps = 0;
    await _feed();
  }

  /// Polls the open offers every 2 s until one for [forTrip] (or
  /// [timeout]). Returns (offer, other trips offered meanwhile).
  Future<(Map<String, dynamic>?, Set<String>)> waitOffer(
    String forTrip,
    Duration timeout, {
    bool Function()? stop,
  }) async {
    final others = <String>{};
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end) && !(stop?.call() ?? false)) {
      final page = await api.openOffers();
      final items = page.map?['items'];
      if (items is List) {
        for (final o in items.whereType<Map>()) {
          final offer = Map<String, dynamic>.from(o);
          if (offer['tripId'] == forTrip) return (offer, others);
          if (offer['tripId'] is String) others.add(offer['tripId'] as String);
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return (null, others);
  }

  /// The trip as the driver sees it (`GET /trips/{id}`).
  Future<Map<String, dynamic>?> trip(String id) async {
    final answer = await api.trip(id);
    return answer.ok ? answer.map : null;
  }

  /// One trip command with the trip's current version (read first); one
  /// retry on 409 version_mismatch.
  Future<ApiAnswer> step(
    String id,
    String name, [
    Map<String, Object?> extra = const {},
  ]) async {
    ApiAnswer? last;
    for (var i = 0; i < 2; i++) {
      final view = await trip(id);
      final version = view?['version'];
      if (version is! num) {
        return last ?? const ApiAnswer(0, null, error: 'no trip version');
      }
      last = await api.tripStep(id, name, version.toInt(), extra);
      if (last.ok || last.reason != 'version_mismatch') return last;
    }
    return last!;
  }

  /// Offline at the end (feeder stopped first). Returns what was done.
  Future<String> goOffline() async {
    stopFeeder();
    final read = await readProfile();
    if (!read.ok) return 'profile ${read.short}';
    if (onlineStatus == 'offline') {
      online = false;
      return 'already offline';
    }
    final version = profile?['version'];
    if (version is! num) return 'profile has no version';
    final answer = await api.availability(version.toInt(), 'offline');
    await readProfile();
    online = onlineStatus != 'offline';
    return 'availability offline ${answer.short}; server ${onlineStatus ?? '?'}';
  }

  void close() {
    stopFeeder();
    api.close();
  }

  /// A point [north] m north and [east] m east of ([lat], [lng]).
  static (double, double) offset(
    double lat,
    double lng, {
    double north = 0,
    double east = 0,
  }) => (
    lat + north / 111320.0,
    lng + east / (111320.0 * math.cos(lat * math.pi / 180)),
  );

  static double distanceMeters(
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    const r = 6371000.0;
    final dLat = (bLat - aLat) * math.pi / 180;
    final dLng = (bLng - aLng) * math.pi / 180;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(aLat * math.pi / 180) *
            math.cos(bLat * math.pi / 180) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  static double _bearing(double aLat, double aLng, double bLat, double bLng) {
    final p1 = aLat * math.pi / 180, p2 = bLat * math.pi / 180;
    final dl = (bLng - aLng) * math.pi / 180;
    final y = math.sin(dl) * math.cos(p2);
    final x =
        math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    final deg = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    return deg >= 360 ? 0 : deg;
  }
}
