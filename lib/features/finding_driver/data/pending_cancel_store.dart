import 'dart:async';
import 'dart:convert';

import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/contracts/cancel_reasons.dart';
import 'package:movera_rider/core/contracts/money.dart';
import 'package:movera_rider/core/contracts/trip_status.dart';
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
    this.expectedVersion,
    this.whileSearching = false,
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

  /// R-O2: the trip version the rider's screen showed when they tapped
  /// (`expectedVersion`). Null when none was known, and for entries
  /// written before the field existed.
  final int? expectedVersion;

  /// rider-u103: queued from the search, before any driver accepted. Such
  /// a cancel is free; once a driver has accepted, the match overtook it
  /// (RC-03) and it is never replayed on the matched trip.
  final bool whileSearching;

  PendingCancel withKey(String key) => PendingCancel(
    rideId: rideId,
    reasonId: reasonId,
    idempotencyKey: key,
    command: command,
    expectedVersion: expectedVersion,
    whileSearching: whileSearching,
  );

  PendingCancel withReason(String? reason) => PendingCancel(
    rideId: rideId,
    reasonId: reason,
    idempotencyKey: idempotencyKey,
    command: command,
    expectedVersion: expectedVersion,
    whileSearching: whileSearching,
  );

  /// The same command for a newer trip [version] the outbox re-read before
  /// replaying it (R-O2). A new body is a new request, so it gets a new
  /// key; the old one was never applied (the re-read shows the trip still
  /// open).
  PendingCancel forVersion(int? version) => PendingCancel(
    rideId: rideId,
    reasonId: reasonId,
    idempotencyKey: newIdempotencyKey('ride-cancel'),
    command: command,
    expectedVersion: version,
    whileSearching: whileSearching,
  );

  /// The request body: the rider's reason and, when known, the version.
  /// Always the same for one entry, so its key never covers two bodies.
  Map<String, dynamic> body([String? fallbackReason]) => {
    ...CancelReasonCodes.riderCancelBody(reasonId ?? fallbackReason),
    'expectedVersion': ?expectedVersion,
  };

  Map<String, dynamic> toJson() => {
    'rideId': rideId,
    'reasonId': reasonId,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    'command': command.pathSegment,
    'expectedVersion': ?expectedVersion,
    if (whileSearching) 'whileSearching': true,
  };

  factory PendingCancel.fromJson(Map<String, dynamic> json) => PendingCancel(
    rideId: json['rideId'] as String,
    reasonId: json['reasonId'] as String?,
    idempotencyKey: json['idempotencyKey'] as String?,
    command: PendingCancelCommand.parse(json['command']),
    expectedVersion: (json['expectedVersion'] as num?)?.toInt(),
    whileSearching: json['whileSearching'] == true,
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

  /// R-O2: re-read before replaying, the trip had moved on so the command
  /// no longer applies (a queued cancel for a rider now on board, an
  /// end-early for a trip not started): it was dropped, never sent, and
  /// the ride goes on. The rider is told their ride changed.
  stale,
}

/// A flush outcome for one ride, as reported on [PendingCancelStore.outcomes].
class PendingCancelOutcome {
  const PendingCancelOutcome({
    required this.rideId,
    required this.command,
    required this.result,
    this.reasonId,
    this.charged,
    this.fee,
  });

  final String rideId;
  final PendingCancelCommand command;
  final PendingCancelResult result;

  /// rider-u32: what the queued entry carried and what the server answered
  /// when it was [PendingCancelResult.sent], so the screen that later sees
  /// the trip closed can file it right: the rider's reason, the trip's
  /// `fare` after an end-early (what they pay), and a cancel's
  /// `cancellation.fee`. Null when unknown.
  final String? reasonId;
  final Money? charged;
  final Money? fee;
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

/// R-O3: a refusal whose projection says the rider already cancelled the
/// trip. A second cancel is quietly fine (owner decision): the app shows
/// the trip as cancelled instead of an error.
bool alreadyCancelledByRider(Object error) {
  if (error is! ApiError) return false;
  final status = TripStatusWire.parse(error.projection?['status']);
  return status == TripStatus.cancelledByRider;
}

class PendingCancelStore {
  static const _key = 'movera_pending_cancels';

  static final StreamController<PendingCancelOutcome> _outcomes =
      StreamController<PendingCancelOutcome>.broadcast();

  /// Every answer an outbox flush got (RC-02/RC-03), so a screen still
  /// showing the ride can tell the rider instead of the entry vanishing.
  static Stream<PendingCancelOutcome> get outcomes => _outcomes.stream;

  static void report(PendingCancelOutcome outcome) {
    if (outcome.result == PendingCancelResult.refused ||
        outcome.result == PendingCancelResult.stale) {
      _notices[outcome.rideId] = outcome.result;
    } else {
      _notices.remove(outcome.rideId);
    }
    if (outcome.result == PendingCancelResult.sent) {
      _delivered[outcome.rideId] = outcome;
    } else {
      _delivered.remove(outcome.rideId);
    }
    _outcomes.add(outcome);
  }

  /// rider-u32: commands a flush delivered (`sent`), kept until the screen
  /// that sees the trip closed on realtime takes them. A launch flush can
  /// deliver an end-early before Waiting exists (a cold restore), and the
  /// projection that follows says nothing about the reason or the amount.
  static final Map<String, PendingCancelOutcome> _delivered = {};

  /// The delivered command for [rideId], once; null when none was.
  static PendingCancelOutcome? takeDelivered(String rideId) =>
      _delivered.remove(rideId);

  /// Refusals and stale drops nobody has told the rider about yet. A flush
  /// at launch can answer before the ride's screen exists (a cold restore);
  /// the screen takes it when it opens (R-O2: "tell the rider").
  static final Map<String, PendingCancelResult> _notices = {};

  /// The untold refused/stale answer for [rideId], once.
  static PendingCancelResult? takeNotice(String rideId) =>
      _notices.remove(rideId);

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
        expectedVersion: (decoded['expectedVersion'] as num?)?.toInt(),
        whileSearching: decoded['whileSearching'] == true,
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
    int? expectedVersion,
    bool whileSearching = false,
  }) async {
    final existing = await find(rideId);
    if (existing != null &&
        existing.command == command &&
        existing.whileSearching == whileSearching &&
        existing.idempotencyKey != null) {
      return existing;
    }
    final entry = PendingCancel(
      rideId: rideId,
      reasonId: reasonId ?? existing?.reasonId,
      idempotencyKey:
          idempotencyKey ?? newIdempotencyKey('ride-cancel'),
      command: command,
      expectedVersion: expectedVersion,
      whileSearching: whileSearching,
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
