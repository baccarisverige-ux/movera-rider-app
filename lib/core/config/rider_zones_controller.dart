import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_zones.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';

/// The last `GET /rider/zones` answer, kept on the device.
abstract class RiderZonesStore {
  Future<Map<String, Object?>?> read();
  Future<void> write(Map<String, Object?> answer);
}

class PrefsRiderZonesStore implements RiderZonesStore {
  const PrefsRiderZonesStore();

  static const key = 'movera_rider_zones_v1';

  @override
  Future<Map<String, Object?>?> read() async {
    final prefs = await PreferencesStore.load();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  @override
  Future<void> write(Map<String, Object?> answer) async {
    final prefs = await PreferencesStore.load();
    await prefs.setString(key, jsonEncode(answer));
  }
}

class MemoryRiderZonesStore implements RiderZonesStore {
  Map<String, Object?>? answer;

  @override
  Future<Map<String, Object?>?> read() async => answer;

  @override
  Future<void> write(Map<String, Object?> answer) async {
    this.answer = answer;
  }
}

/// Zones from the server (contract v0.11.0 §21): `GET /rider/zones` on
/// start and on `config_published` with doc `zones`; the last answer is
/// kept on the device and used until the server answers. Without [api]
/// (the demo) the built-in sample zones stay. Never throws to its callers.
class RiderZonesController extends ChangeNotifier {
  RiderZonesController({
    this.api,
    RiderZonesStore? store,
    List<Duration>? retryDelays,
  }) : _store = store ?? const PrefsRiderZonesStore(),
       retryDelays = retryDelays ?? defaultRetryDelays;

  /// Owner 2026-11-10: a failed read while a kept list is in use is tried
  /// again after each of these delays (bounded: 3 more tries).
  static const defaultRetryDelays = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  final List<Duration> retryDelays;

  static const path = '/api/v1/rider/zones';

  final ApiClient? api;
  final RiderZonesStore _store;
  Future<bool>? _inFlight;
  Timer? _retryTimer;
  int _retries = 0;

  List<RiderZone> get zones => RiderZones.all;

  bool _failed = false;

  /// L-a R1/R3: the last read of the server's list failed and no list is in
  /// use yet (a live build with no kept answer). The screen shows an error
  /// with Retry instead of "Checking your area…" for ever.
  bool get failed => _failed && !RiderZones.known;

  /// L-a R1/R3: Retry on that error. Reads the server again; while the
  /// read runs the screen is back on "Checking your area…".
  Future<bool> retry() {
    if (_failed) {
      _failed = false;
      notifyListeners();
    }
    return refresh();
  }

  /// The zones of an answer `{ zones: Zone[] }`; null when it is not one.
  /// A zone that does not parse is left out.
  static List<RiderZone>? parse(Object? answer) {
    if (answer is! Map) return null;
    final raw = answer['zones'];
    if (raw is! List) return null;
    return [
      for (final item in raw)
        if (item is Map && item['open'] != false) ?RiderZone.fromJson(item),
    ];
  }

  /// Uses the kept answer, when there is one.
  Future<void> loadCached() async {
    if (api == null) return;
    try {
      final zones = parse(await _store.read());
      if (zones != null) _use(zones);
    } catch (error) {
      AppLog.warning('rider_zones.cache_ignored', extra: {'error': '$error'});
    }
  }

  /// Reads the server's list. True when it was read.
  Future<bool> refresh() {
    if (api == null) {
      _markFailed();
      return Future.value(false);
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<bool> _fetch({bool retry = false}) async {
    try {
      final raw = await api!.get(path);
      final zones = parse(raw);
      if (zones == null) throw const FormatException('not a zones answer');
      _use(zones);
      _retryTimer?.cancel();
      _retryTimer = null;
      _retries = 0;
      try {
        await _store.write({
          'zones': [for (final zone in zones) zone.toJson()],
        });
      } catch (_) {
        // The list is in use; the next start reads the server again.
      }
      return true;
    } catch (error) {
      AppLog.warning('rider_zones.unavailable', extra: {'error': '$error'});
      _markFailed();
      if (!retry) _retries = 0;
      _scheduleRetry();
      return false;
    }
  }

  /// Owner 2026-11-10: a kept list stays in use when a read fails, so it is
  /// read again after a short delay (bounded by [retryDelays]) instead of
  /// keeping an old list silently. Without a list in use the screen offers
  /// Retry itself.
  void _scheduleRetry() {
    if (!RiderZones.known || _retryTimer != null) return;
    if (_retries >= retryDelays.length) return;
    final delay = retryDelays[_retries++];
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (api == null) return;
      unawaited(
        _inFlight ??= _fetch(retry: true).whenComplete(() => _inFlight = null),
      );
    });
  }

  /// Kept answer, then the server's.
  Future<void> start() async {
    await loadCached();
    unawaited(refresh());
  }

  /// A config stream event: a `zones` publish reads the list again.
  void onConfigEvent(Map<String, Object?> event) {
    if (event['doc'] == 'zones') unawaited(refresh());
  }

  void _markFailed() {
    if (_failed) return;
    _failed = true;
    if (!RiderZones.known) notifyListeners();
  }

  void _use(List<RiderZone> zones) {
    _failed = false;
    RiderZones.useServer(zones);
    notifyListeners();
  }
}
