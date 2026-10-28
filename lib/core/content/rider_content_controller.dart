import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/constants/app_version.dart' as build;
import 'package:movera_rider/core/content/rider_content.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';

/// The last content answer per zone and the accepted terms version, kept
/// on the device.
abstract class RiderContentStore {
  Future<Map<String, Object?>?> read(String zoneId);
  Future<void> write(String zoneId, Map<String, Object?> answer);
  Future<int?> acceptedLegalVersion();
  Future<void> writeAcceptedLegalVersion(int version);
}

class PrefsRiderContentStore implements RiderContentStore {
  const PrefsRiderContentStore();

  static String keyOf(String zoneId) => 'movera_rider_content_v1_$zoneId';
  static const acceptedKey = 'movera_rider_terms_accepted_v1';

  @override
  Future<Map<String, Object?>?> read(String zoneId) async {
    final prefs = await PreferencesStore.load();
    final raw = prefs.getString(keyOf(zoneId));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  @override
  Future<void> write(String zoneId, Map<String, Object?> answer) async {
    final prefs = await PreferencesStore.load();
    await prefs.setString(keyOf(zoneId), jsonEncode(answer));
  }

  @override
  Future<int?> acceptedLegalVersion() async {
    final prefs = await PreferencesStore.load();
    return prefs.getInt(acceptedKey);
  }

  @override
  Future<void> writeAcceptedLegalVersion(int version) async {
    final prefs = await PreferencesStore.load();
    await prefs.setInt(acceptedKey, version);
  }
}

class MemoryRiderContentStore implements RiderContentStore {
  final Map<String, Map<String, Object?>> answers = {};
  int? accepted;

  @override
  Future<Map<String, Object?>?> read(String zoneId) async => answers[zoneId];

  @override
  Future<void> write(String zoneId, Map<String, Object?> answer) async {
    answers[zoneId] = answer;
  }

  @override
  Future<int?> acceptedLegalVersion() async => accepted;

  @override
  Future<void> writeAcceptedLegalVersion(int version) async {
    accepted = version;
  }
}

/// Content for the rider app (contract v0.10.0 §19): `GET /rider/content
/// ?zoneId` on start and on `config_published` with doc `content`; the last
/// answer is kept on the device. Without [api] (the demo) the app keeps its
/// own local content: no banners, no gates. Never throws to its callers.
class RiderContentController extends ChangeNotifier {
  RiderContentController({
    this.api,
    RiderContentStore? store,
    this.appVersion = build.appVersion,
    ValueListenable<bool>? onTrip,
    DateTime Function()? clock,
  }) : _store = store ?? const PrefsRiderContentStore(),
       onTrip = onTrip ?? ValueNotifier(false),
       _clock = clock ?? DateTime.now {
    this.onTrip.addListener(notifyListeners);
  }

  static const path = '/api/v1/rider/content';
  static const acceptPath = '/api/v1/account/terms/accept';

  final ApiClient? api;
  final RiderContentStore _store;
  final String appVersion;

  /// True while the rider has a live ride: no full screen then.
  final ValueListenable<bool> onTrip;
  final DateTime Function() _clock;

  RiderContent _content = RiderContent.empty;
  RiderContent get content => _content;

  String? _zoneId;
  int? _accepted;
  bool _recommendedClosed = false;
  bool _started = false;

  /// The legal item of this app start: from the kept answer and the first
  /// answer after start. A later publish shows at the next start.
  ContentItem? _legalAtStart;
  bool _startFetched = false;
  bool _disposed = false;

  DateTime get now => _clock();

  ContentDecision get decision => ContentDecision.decide(
    content: _content,
    now: now,
    appVersion: appVersion,
    onTrip: onTrip.value,
    legalAtStart: _legalAtStart,
    acceptedLegalVersion: _accepted,
    recommendedClosed: _recommendedClosed,
  );

  List<ContentItem> get banners => _content.banners(now);
  ContentItem? get help => _content.help(now);

  /// Reads the kept answer, then the server's, for [zoneId].
  Future<void> start(String zoneId) async {
    if (api == null) return;
    final moved = _zoneId != zoneId;
    _zoneId = zoneId;
    if (!_started) {
      _started = true;
      try {
        _accepted = await _store.acceptedLegalVersion();
      } catch (error) {
        AppLog.warning(
          'rider_content.ignored',
          extra: {'error': error.toString()},
        );
      }
    }
    if (moved) {
      try {
        final kept = RiderContent.fromJson(await _store.read(zoneId));
        if (kept != null) _set(kept, armsLegal: !_startFetched);
      } catch (error) {
        AppLog.warning(
          'rider_content.cache_read_failed',
          extra: {'error': error.toString()},
        );
      }
    }
    await refresh();
  }

  /// Asks the server again; keeps what it had when that fails.
  Future<void> refresh() async {
    final client = api;
    final zoneId = _zoneId;
    if (client == null || zoneId == null) return;
    try {
      final raw = await client.get(
        '$path?zoneId=${Uri.encodeComponent(zoneId)}',
      );
      final parsed = RiderContent.fromJson(raw);
      if (parsed == null) throw const FormatException('not a ContentList');
      if (zoneId != _zoneId) return;
      _set(parsed, armsLegal: !_startFetched);
      _startFetched = true;
      try {
        await _store.write(zoneId, Map<String, Object?>.from(raw));
      } catch (error) {
        AppLog.warning(
          'rider_content.ignored',
          extra: {'error': error.toString()},
        );
      }
    } catch (error) {
      AppLog.warning(
        'rider_content.fetch_failed',
        extra: {'zoneId': zoneId, 'error': error.toString()},
      );
    }
  }

  void _set(RiderContent next, {required bool armsLegal}) {
    _content = next;
    if (armsLegal) _legalAtStart = next.legal(now);
    if (!_disposed) notifyListeners();
  }

  /// A server-sent event of `/rider/config/stream`.
  void onConfigEvent(Map<String, Object?> data) {
    if (data['kind'] == 'config_published' && data['doc'] == 'content') {
      unawaited(refresh());
    }
  }

  /// `POST /account/terms/accept { contentVersion }`. True when stored.
  Future<bool> acceptTerms() async {
    final legal = decision.acceptTerms;
    final client = api;
    if (legal == null || client == null) return true;
    try {
      await client.post(
        acceptPath,
        body: {'contentVersion': legal.version},
        idempotencyKey: newIdempotencyKey('terms-accept'),
      );
    } catch (error) {
      AppLog.warning(
        'rider_content.accept_failed',
        extra: {'error': error.toString()},
      );
      return false;
    }
    _accepted = legal.version;
    try {
      await _store.writeAcceptedLegalVersion(legal.version);
    } catch (error) {
      AppLog.warning(
        'rider_content.ignored',
        extra: {'error': error.toString()},
      );
    }
    if (!_disposed) notifyListeners();
    return true;
  }

  void closeRecommendedUpdate() {
    _recommendedClosed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    onTrip.removeListener(notifyListeners);
    super.dispose();
  }
}
