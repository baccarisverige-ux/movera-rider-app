import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/config/rider_app_config.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';

/// The last good RiderAppConfig per zone, kept on the device as the raw
/// document so a start without network reads yesterday's settings.
abstract class RiderConfigCache {
  Future<Map<String, Object?>?> read(String zoneId);
  Future<void> write(String zoneId, Map<String, Object?> document);
}

class PrefsRiderConfigCache implements RiderConfigCache {
  const PrefsRiderConfigCache();

  static String keyOf(String zoneId) => 'movera_rider_config_v1_$zoneId';

  @override
  Future<Map<String, Object?>?> read(String zoneId) async {
    final prefs = await PreferencesStore.load();
    final raw = prefs.getString(keyOf(zoneId));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  @override
  Future<void> write(String zoneId, Map<String, Object?> document) async {
    final prefs = await PreferencesStore.load();
    await prefs.setString(keyOf(zoneId), jsonEncode(document));
  }
}

class MemoryRiderConfigCache implements RiderConfigCache {
  final Map<String, Map<String, Object?>> documents = {};

  @override
  Future<Map<String, Object?>?> read(String zoneId) async => documents[zoneId];

  @override
  Future<void> write(String zoneId, Map<String, Object?> document) async {
    documents[zoneId] = document;
  }
}

/// RiderAppConfig from the server (contract §6, owner 2026-10-27):
/// `GET /rider/config?zoneId` on start and whenever `config_published`
/// arrives on `/rider/config/stream`; the last good document per zone is
/// kept (memory and device) and an older or equal version is ignored. With
/// no server: the last document received, else the built-in seed. Never
/// throws to its callers.
class ApiRiderConfigRepository extends ChangeNotifier
    implements RiderConfigRepository {
  ApiRiderConfigRepository({
    required ApiClient api,
    RiderConfigCache? cache,
    this.homeZoneId = 'Z001',
    this.retryAfter = const Duration(seconds: 5),
  }) : _api = api,
       _cache = cache ?? const PrefsRiderConfigCache();

  static const path = '/api/v1/rider/config';
  static const streamPath = '/api/v1/rider/config/stream';

  final ApiClient _api;
  final RiderConfigCache _cache;

  /// The zone [current] answers for until the rider's zone is known.
  String homeZoneId;
  final Duration retryAfter;
  final Map<String, RiderAppConfig> _documents = {};
  final Map<String, Future<RiderAppConfig?>> _inFlight = {};
  StreamSubscription<String>? _stream;
  Timer? _retry;
  String? _watching;
  bool _disposed = false;

  /// Every event of the stream, for the other documents published on it
  /// (contract v0.10.0: `config_published` with doc `content`).
  final List<void Function(Map<String, Object?> event)> eventTaps = [];

  static RiderAppConfig _seed(String zoneId) =>
      SeedRiderConfigRepository.seedFor(zoneId);

  @override
  Future<RiderAppConfig> current() => forZone(homeZoneId);

  @override
  Future<RiderAppConfig> forZone(String zoneId) async {
    final known = _documents[zoneId];
    if (known != null) return known;
    return await refresh(zoneId) ?? await _fallback(zoneId);
  }

  /// Asks the server for [zoneId]'s document. Returns the document kept for
  /// the zone after the answer, or null when the server could not be read.
  Future<RiderAppConfig?> refresh(String zoneId) {
    return _inFlight[zoneId] ??= _fetch(zoneId).whenComplete(() {
      // A block, not an arrow: remove() returns this future itself.
      _inFlight.remove(zoneId);
    });
  }

  Future<RiderAppConfig?> _fetch(String zoneId) async {
    try {
      final raw = await _api.get('$path?zoneId=${Uri.encodeComponent(zoneId)}');
      final parsed = RiderAppConfig.fromJson(raw, fallback: _seed(zoneId));
      if (parsed == null) throw const FormatException('not a RiderAppConfig');
      _keep(zoneId, parsed);
      if (_documents[zoneId] == parsed) {
        try {
          await _cache.write(zoneId, Map<String, Object?>.from(raw));
        } catch (error) {
          AppLog.warning(
            'rider_config.cache_write_failed',
            extra: {'error': error.toString()},
          );
        }
      }
      return _documents[zoneId];
    } catch (error) {
      AppLog.warning(
        'rider_config.fetch_failed',
        extra: {'zoneId': zoneId, 'error': error.toString()},
      );
      return null;
    }
  }

  /// Keeps [next] unless the zone already has the same or a newer version.
  void _keep(String zoneId, RiderAppConfig next) {
    final known = _documents[zoneId];
    if (known != null && known.version >= next.version) return;
    _documents[zoneId] = next;
    if (!_disposed) notifyListeners();
  }

  Future<RiderAppConfig> _fallback(String zoneId) async {
    try {
      final cached = await _cache.read(zoneId);
      final parsed = RiderAppConfig.fromJson(cached, fallback: _seed(zoneId));
      if (parsed != null) {
        _keep(zoneId, parsed);
        return _documents[zoneId]!;
      }
    } catch (error) {
      AppLog.warning(
        'rider_config.cache_read_failed',
        extra: {'error': error.toString()},
      );
    }
    return _seed(zoneId);
  }

  /// Listens to `config_published` for [zoneId] and fetches the document on
  /// each one with a newer version; reconnects after [retryAfter] when the
  /// stream ends or fails. A second call moves the watch to the new zone.
  Future<void> watch(String zoneId) async {
    if (_watching == zoneId && _stream != null) return;
    await _stopStream();
    _watching = zoneId;
    unawaited(refresh(zoneId));
    await _connect(zoneId);
  }

  Future<void> _connect(String zoneId) async {
    if (_disposed || _watching != zoneId) return;
    try {
      final lines = await _api.openEventStream(
        '$streamPath?zoneId=${Uri.encodeComponent(zoneId)}',
        lastEventId: _documents[zoneId]?.version.toString(),
      );
      final events = ConfigEventParser();
      _stream = lines.listen(
        (line) {
          final data = events.add(line);
          if (data == null) return;
          for (final tap in List.of(eventTaps)) {
            tap(data);
          }
          // Content has its own read (RiderContentController).
          if (data['doc'] == 'content') return;
          final version = data['version'];
          final known = _documents[zoneId]?.version ?? 0;
          if (data['kind'] == 'config_published' &&
              (version is! int || version > known)) {
            unawaited(refresh(zoneId));
          }
        },
        onDone: () => _reconnect(zoneId),
        onError: (Object _) => _reconnect(zoneId),
        cancelOnError: true,
      );
    } catch (error) {
      AppLog.warning(
        'rider_config.stream_failed',
        extra: {'error': error.toString()},
      );
      _reconnect(zoneId);
    }
  }

  void _reconnect(String zoneId) {
    _stream = null;
    if (_disposed || _watching != zoneId) return;
    _retry?.cancel();
    _retry = Timer(retryAfter, () {
      // Whatever was published while the stream was down comes first.
      unawaited(refresh(zoneId));
      unawaited(_connect(zoneId));
    });
  }

  Future<void> _stopStream() async {
    _retry?.cancel();
    _retry = null;
    final stream = _stream;
    _stream = null;
    await stream?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _watching = null;
    unawaited(_stopStream());
    super.dispose();
  }
}

/// Server-Sent Events: lines in, each event's JSON `data` out (one per
/// blank line). Comments and other fields are skipped.
class ConfigEventParser {
  final StringBuffer _data = StringBuffer();

  /// The event that [line] completes, or null.
  Map<String, Object?>? add(String line) {
    if (line.isEmpty) {
      final text = _data.toString();
      _data.clear();
      if (text.isEmpty) return null;
      try {
        final decoded = jsonDecode(text);
        return decoded is Map ? Map<String, Object?>.from(decoded) : null;
      } on FormatException {
        return null;
      }
    }
    if (line.startsWith('data:')) {
      if (_data.isNotEmpty) _data.write('\n');
      _data.write(line.substring(5).trimLeft());
    }
    return null;
  }
}
