import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// G9 live 2026-11-02: the rider's "Message" badge counted messages the
/// rider had already read again after a reload. This keeps, per active
/// trip, only WHEN the rider last read the chat — a trip id and a time,
/// never a message or its text (owner 2026-10-30: messages are never
/// stored in the app). Forgotten when the trip's chat ends.
abstract final class ChatReadMarks {
  static const String storageKey = 'movera_chat_read_marks_v1';

  static final Map<String, DateTime> _marks = <String, DateTime>{};
  static bool _loaded = false;

  /// Reads the marks once (app start); a refused or broken read leaves none.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        final at = value is String ? DateTime.tryParse(value) : null;
        if (key is String && at != null) _marks[key] = at.toUtc();
      });
    } catch (_) {
      // Nothing to restore: the badge counts as before.
    }
  }

  /// When the rider last read [rideId]'s chat, or null.
  static DateTime? of(String rideId) => _marks[rideId.trim()];

  /// The rider read [rideId]'s chat up to [at] (the newest message shown).
  static void mark(String rideId, DateTime at) {
    final key = rideId.trim();
    if (key.isEmpty) return;
    final known = _marks[key];
    if (known != null && !at.isAfter(known)) return;
    _marks[key] = at.toUtc();
    _save();
  }

  /// The trip's chat ended: its mark goes too.
  static void forget(String rideId) {
    if (_marks.remove(rideId.trim()) != null) _save();
  }

  static void forgetAll() {
    if (_marks.isEmpty) return;
    _marks.clear();
    _save();
  }

  static void _save() {
    final copy = {
      for (final entry in _marks.entries)
        entry.key: entry.value.toIso8601String(),
    };
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(storageKey, jsonEncode(copy)))
        .catchError((Object _) => false);
  }

  /// Tests: forget everything in memory and read storage again next time.
  static void resetForTest() {
    _marks.clear();
    _loaded = false;
  }
}
