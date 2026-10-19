import 'dart:async';
import 'dart:convert';

import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';

/// A ride cancellation the server never acknowledged.
///
/// Finding and Waiting/in-trip both write the intent here and ask the backend
/// first. When the backend call keeps failing (offline, a dropped connection) the request must
/// not just vanish when the process exits — a later session, or the next
/// reconnect, needs to find it and try again.
///
/// D-020: every entry carries the one idempotency key minted for it, so a
/// retry after a relaunch is recognisably the same request to the server
/// instead of a brand-new cancel each launch.
class PendingCancel {
  const PendingCancel({
    required this.rideId,
    this.reasonId,
    this.idempotencyKey,
    this.command = PendingCancelCommand.cancel,
  });

  final String rideId;
  final String? reasonId;

  /// Null only for entries written by builds before D-020; the flush mints
  /// and persists one the first time it sees such an entry.
  final String? idempotencyKey;

  /// The rider command this entry stands for (RC-02): `cancel` before
  /// boarding, `end-early` once on board. Entries written before the field
  /// existed were all `cancel`.
  final PendingCancelCommand command;

  PendingCancel withKey(String key) => PendingCancel(
    rideId: rideId,
    reasonId: reasonId,
    idempotencyKey: key,
    command: command,
  );

  PendingCancel withReason(String? reason) => PendingCancel(
    rideId: rideId,
    reasonId: reason,
    idempotencyKey: idempotencyKey,
    command: command,
  );

  Map<String, dynamic> toJson() => {
    'rideId': rideId,
    'reasonId': reasonId,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    'command': command.pathSegment,
  };

  factory PendingCancel.fromJson(Map<String, dynamic> json) => PendingCancel(
    rideId: json['rideId'] as String,
    reasonId: json['reasonId'] as String?,
    idempotencyKey: json['idempotencyKey'] as String?,
    command: PendingCancelCommand.parse(json['command']),
  );
}

/// The two rider commands that end a ride (contract v0.3.0).
enum PendingCancelCommand {
  /// Before boarding: `POST …/cancel`.
  cancel('cancel'),

  /// On board: `POST …/end-early` (pay for the distance driven).
  endEarly('end-early');

  const PendingCancelCommand(this.pathSegment);

  /// The last path segment of the command endpoint.
  final String pathSegment;

  /// Unknown or missing values are `cancel`, as every pre-RC-02 entry was.
  static PendingCancelCommand parse(Object? raw) {
    for (final command in values) {
      if (command.pathSegment == raw) return command;
    }
    return cancel;
  }
}

/// What one outbox flush learned about an entry.
enum PendingCancelResult {
  /// The server accepted the command.
  sent,

  /// The server refused it (409/422) and the ride is still live: the
  /// rider's cancel did not happen and the ride goes on.
  refused,

  /// The ride is gone or already over (404/410, or a refusal for a ride
  /// that has ended): nothing is left to cancel.
  gone,
}

/// A flush outcome for one ride, as reported on [PendingCancelStore.outcomes].
class PendingCancelOutcome {
  const PendingCancelOutcome({
    required this.rideId,
    required this.command,
    required this.result,
  });

  final String rideId;
  final PendingCancelCommand command;
  final PendingCancelResult result;
}

/// True when a cancel request failed in a way no retry can fix: the server
/// no longer knows the ride (404/410) or refuses the transition because the
/// ride is already finished/cancelled (409/422). Those entries must leave the
/// outbox instead of being retried forever (D-020).
bool isPermanentCancelFailure(Object error) {
  if (error is! ApiError) return false;
  final status = error.statusCode;
  return status == 404 || status == 409 || status == 410 || status == 422;
}

class PendingCancelStore {
  static const _key = 'movera_pending_cancels';

  static final StreamController<PendingCancelOutcome> _outcomes =
      StreamController<PendingCancelOutcome>.broadcast();

  /// Every answer an outbox flush got (RC-02/RC-03), so a screen still
  /// showing the ride can tell the rider instead of the entry vanishing.
  static Stream<PendingCancelOutcome> get outcomes => _outcomes.stream;

  static void report(PendingCancelOutcome outcome) => _outcomes.add(outcome);

  /// Decodes one stored entry, or null when it is corrupt (not JSON, not an
  /// object, no usable rideId). CODE-17: one bad entry used to throw out of
  /// every read, so no later cancel could be queued or flushed at all.
  static PendingCancel? _decode(String entry) {
    try {
      final decoded = jsonDecode(entry);
      if (decoded is! Map<String, dynamic>) return null;
      final rideId = decoded['rideId'];
      if (rideId is! String || rideId.trim().isEmpty) return null;
      final reasonId = decoded['reasonId'];
      final key = decoded['idempotencyKey'];
      return PendingCancel(
        rideId: rideId,
        reasonId: reasonId is String ? reasonId : null,
        idempotencyKey: key is String && key.isNotEmpty ? key : null,
        command: PendingCancelCommand.parse(decoded['command']),
      );
    } catch (_) {
      return null;
    }
  }

  static void _logCorrupt(int count) {
    AppLog.warning(
      'ride.cancel.outbox_corrupt_entry_skipped',
      extra: {'count': count},
    );
  }

  /// Every readable entry; corrupt ones are skipped and logged.
  static Future<List<PendingCancel>> all() async {
    final prefs = await PreferencesStore.load();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    final entries = <PendingCancel>[];
    var corrupt = 0;
    for (final entry in raw) {
      final decoded = _decode(entry);
      if (decoded == null) {
        corrupt += 1;
      } else {
        entries.add(decoded);
      }
    }
    if (corrupt > 0) _logCorrupt(corrupt);
    return entries;
  }

  /// The stored list without corrupt entries and without [rideId]'s entry.
  /// Rewriting the list therefore also drops anything unreadable.
  static List<String> _othersThan(List<String> existing, String rideId) {
    final kept = <String>[];
    var corrupt = 0;
    for (final entry in existing) {
      final decoded = _decode(entry);
      if (decoded == null) {
        corrupt += 1;
      } else if (decoded.rideId != rideId) {
        kept.add(entry);
      }
    }
    if (corrupt > 0) _logCorrupt(corrupt);
    return kept;
  }

  static Future<PendingCancel?> find(String rideId) async {
    for (final entry in await all()) {
      if (entry.rideId == rideId) return entry;
    }
    return null;
  }

  static Future<void> add(PendingCancel cancel) async {
    final prefs = await PreferencesStore.load();
    final existing = prefs.getStringList(_key) ?? const <String>[];
    final withoutSameRide = _othersThan(existing, cancel.rideId);
    await prefs.setStringList(_key, [
      ...withoutSameRide,
      jsonEncode(cancel.toJson()),
    ]);
  }

  /// Records the rider's intent to cancel [rideId] before the request is
  /// sent, reusing the entry (and its idempotency key) if one already exists
  /// for the same [command]. A different command is a different request,
  /// so it replaces the entry with its own key.
  static Future<PendingCancel> enqueue({
    required String rideId,
    String? reasonId,
    String? idempotencyKey,
    PendingCancelCommand command = PendingCancelCommand.cancel,
  }) async {
    final existing = await find(rideId);
    if (existing != null &&
        existing.command == command &&
        existing.idempotencyKey != null) {
      return existing;
    }
    final entry = PendingCancel(
      rideId: rideId,
      reasonId: reasonId ?? existing?.reasonId,
      idempotencyKey:
          idempotencyKey ?? newIdempotencyKey('ride-cancel'),
      command: command,
    );
    await add(entry);
    return entry;
  }

  static Future<void> remove(String rideId) async {
    final prefs = await PreferencesStore.load();
    final existing = prefs.getStringList(_key) ?? const <String>[];
    await prefs.setStringList(_key, _othersThan(existing, rideId));
  }

  /// Adds the rider's optional reason to a cancel that is still queued, so
  /// the retried request carries it. Keeps the entry's idempotency key.
  /// Returns false when nothing for [rideId] is queued.
  static Future<bool> attachReason(String rideId, String reasonId) async {
    final existing = await find(rideId);
    if (existing == null) return false;
    await add(existing.withReason(reasonId));
    return true;
  }
}
