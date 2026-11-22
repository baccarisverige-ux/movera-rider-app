import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Contract v0.18.148 (`sosPressTime`; owner 2026-11-20 "SOS kept and
/// retried; after 30 min or any refusal ... SOS not sent, call 112"): an SOS
/// Movera has not confirmed yet, kept on the phone so it is sent again after
/// a network loss or an app restart. Its Idempotency-Key and body (with the
/// press time `at`) stay the same, so Movera gets one SOS.
class PendingSos {
  const PendingSos({
    required this.key,
    required this.tripId,
    required this.body,
  });

  final String key;
  final String tripId;
  final Map<String, Object?> body;

  Map<String, Object?> toJson() => {'key': key, 'tripId': tripId, 'body': body};

  static PendingSos? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final trip = json['tripId'];
    final body = json['body'];
    if (key is! String || key.isEmpty || trip is! String || trip.isEmpty) {
      return null;
    }
    if (body is! Map) return null;
    return PendingSos(
      key: key,
      tripId: trip,
      body: Map<String, Object?>.from(body),
    );
  }
}

/// Where the one pending SOS is kept. The key starts with `movera_`, so a
/// sign-out wipes it (UserDataWipe): another rider never sends it. One slot:
/// a newer press replaces an older unconfirmed one.
class PendingSosStore {
  const PendingSosStore();

  static const prefKey = 'movera_pending_sos_v1';

  Future<PendingSos?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefKey);
      return raw == null ? null : PendingSos.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PendingSos sos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, jsonEncode(sos.toJson()));
    } catch (_) {
      // No storage: the in-memory retries still go on.
    }
  }

  /// Clears only the SOS with [key], so a newer press is never dropped.
  Future<void> clear(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = await read();
      if (now == null || now.key == key) await prefs.remove(prefKey);
    } catch (_) {}
  }
}
