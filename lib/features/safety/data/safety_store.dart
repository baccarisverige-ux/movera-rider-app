import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/utils/request_id.dart';
import 'package:movera_rider/features/safety/data/safety_data_sources.dart';
import 'package:movera_rider/features/safety/domain/audio_recording.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';
import 'package:movera_rider/features/safety/domain/phone_e164.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_check_trigger.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:movera_rider/features/safety/domain/trip_share.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SafetyException implements Exception {
  const SafetyException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'SafetyException($code, $message)';
}

/// Cached + remote Safety store. Screens never talk to this type's data sources.
class SafetyStore {
  SafetyStore({
    SafetyLocalDataSource? local,
    SafetyRemoteDataSource? remote,
    ApiClient? api,
  })  : _local = local ?? PreferencesSafetyLocalDataSource(),
        _remote = remote ?? ApiSafetyRemoteDataSource(api ?? AppScope.instance.api);

  static SafetyStore? _shared;
  static SafetyStore get shared => _shared ??= SafetyStore();
  static void resetShared() => _shared = null;

  final SafetyLocalDataSource _local;
  final SafetyRemoteDataSource _remote;
  SafetyCache _cache = SafetyCache();
  bool _loaded = false;
  bool failNextWrite = false;

  SafetyPreferences get preferences => _cache.preferences;
  RidePin get pin => _cache.pin;
  List<EmergencyContact> get contacts => List.unmodifiable(_cache.contacts);
  RideCheckPolicy get rideCheck => _cache.rideCheck;
  List<RideCheckEvent> get rideCheckEvents => List.unmodifiable(_cache.events);

  Future<void> load() async {
    _cache = await _local.load();
    // A cached per-user PIN cannot prove that the current ride still uses it.
    // Never display cached digits after a network failure or while refreshing.
    _cache.pin = RidePin.unavailable;
    try {
      final prefs = await _remote.getPreferences();
      final pin = await _remote.getPin();
      final contacts = await _remote.listContacts();
      final policy = await _remote.getRideCheck();
      _cache.preferences = prefs;
      _cache.pin = pin;
      _cache.contacts = contacts;
      _cache.rideCheck = policy;
      await _local.save(_cache);
    } catch (error, stackTrace) {
      // Offline: cached display data only. PIN/events remain server-authoritative
      // when the real backend is connected. Keep the degraded mode observable.
      AppLog.error(
        'safety.remote_load_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _loaded = true;
  }

  Future<void> _ensure() async {
    if (!_loaded) await load();
  }

  /// rider-r3-1: [keep] runs before the optimistic change and returns how
  /// to undo it. A failed write undoes only its own slice of the cache, so
  /// answers, events, recordings and contacts saved by other writes while
  /// it was in flight stay.
  Future<T> _write<T>(
    Future<T> Function() remote,
    T optimistic,
    void Function(T value) apply, {
    required void Function() Function() keep,
  }) async {
    await _ensure();
    final undo = keep();
    apply(optimistic);
    await _local.save(_cache);
    if (failNextWrite) {
      failNextWrite = false;
      undo();
      await _local.save(_cache);
      throw const SafetyException('SERVER_ERROR', 'Simulated write failure');
    }
    try {
      final confirmed = await remote();
      apply(confirmed);
      await _local.save(_cache);
      return confirmed;
    } catch (error) {
      undo();
      await _local.save(_cache);
      rethrow;
    }
  }

  void Function() _keepPreferences() {
    final previous = _cache.preferences;
    return () => _cache.preferences = previous;
  }

  void Function() _keepContacts() {
    final previous = [..._cache.contacts];
    return () => _cache.contacts = previous;
  }

  void Function() _keepEvent(String eventId) {
    final previous = _cache.events.where((e) => e.eventId == eventId);
    final before = previous.isEmpty ? null : previous.last;
    return () => _cache.events = [
          for (final event in _cache.events)
            if (event.eventId != eventId) event
            else if (before != null) before,
          if (before != null && !_cache.events.any((e) => e.eventId == eventId))
            before,
        ];
  }

  void Function() _keepRecording(String id) {
    final previous = _cache.recordings.where((r) => r.id == id);
    final before = previous.isEmpty ? null : previous.last;
    return () => _cache.recordings = [
          for (final item in _cache.recordings)
            if (item.id != id) item else if (before != null) before,
          if (before != null && !_cache.recordings.any((r) => r.id == id))
            before,
        ];
  }

  Future<SafetyPreferences> patchPreferences(SafetyPreferences next) {
    return _write(
      () => _remote.patchPreferences(next),
      next.copyWith(updatedAt: DateTime.now().toUtc()),
      (value) => _cache.preferences = value,
      keep: _keepPreferences,
    );
  }

  Future<RidePin> rotatePin({String? idempotencyKey}) async {
    await _ensure();
    if (failNextWrite) {
      failNextWrite = false;
      throw const SafetyException('SERVER_ERROR', 'Simulated write failure');
    }
    final confirmed = await _remote.rotatePin(idempotencyKey: idempotencyKey);
    _cache.pin = confirmed.copyWith(requiredForStart: _cache.preferences.pinRequired);
    await _local.save(_cache);
    return _cache.pin;
  }

  Future<EmergencyContact> createContact({
    required String name,
    required String phone,
    String relationship = 'Other',
    bool shareTrips = false,
    bool isEnabled = true,
    String? idempotencyKey,
  }) async {
    await _ensure();
    if (_cache.contacts.length >= kMaxEmergencyContacts) {
      throw SafetyException('CONTACT_LIMIT', L10n.current.contactLimit);
    }
    final e164 = SwedishPhone.toE164(phone);
    if (e164 == null) {
      throw SafetyException('INVALID_PHONE', L10n.current.contactInvalidPhone);
    }
    if (_cache.contacts.any((c) => c.phoneE164 == e164)) {
      throw SafetyException(
        'DUPLICATE_PHONE',
        L10n.current.contactDuplicatePhone,
      );
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw SafetyException('INVALID_NAME', L10n.current.contactInvalidName);
    }
    final now = DateTime.now().toUtc();
    final contact = EmergencyContact(
      id: 'ec_${newRequestId()}',
      userId: _cache.preferences.userId,
      name: trimmed,
      phoneE164: e164,
      relationship: kEmergencyContactRelationships.contains(relationship)
          ? relationship
          : 'Other',
      isPrimary: _cache.contacts.isEmpty,
      shareTrips: shareTrips,
      isEnabled: isEnabled,
      createdAt: now,
      updatedAt: now,
    );
    return _write(
      () => _remote.createContact(contact, idempotencyKey: idempotencyKey),
      contact,
      (value) {
        // FLOW-20: the confirmed row replaces the optimistic one even when
        // the server assigns its own id.
        final next = [
          ..._cache.contacts.where(
            (c) => c.id != value.id && c.id != contact.id,
          ),
          value,
        ];
        if (value.isPrimary) {
          _cache.contacts = [
            for (final item in next)
              item.copyWith(isPrimary: item.id == value.id),
          ];
        } else {
          _cache.contacts = next;
        }
      },
      keep: _keepContacts,
    );
  }

  Future<EmergencyContact> updateContact(EmergencyContact contact) async {
    final e164 = SwedishPhone.toE164(contact.phoneE164) ??
        (RegExp(r'^\+46\d{7,10}$').hasMatch(contact.phoneE164)
            ? contact.phoneE164
            : null);
    if (e164 == null) {
      throw SafetyException('INVALID_PHONE', L10n.current.contactInvalidPhone);
    }
    if (contact.name.trim().isEmpty) {
      throw SafetyException('INVALID_NAME', L10n.current.contactInvalidName);
    }
    if (_cache.contacts.any((c) => c.phoneE164 == e164 && c.id != contact.id)) {
      throw SafetyException(
        'DUPLICATE_PHONE',
        L10n.current.contactDuplicatePhone,
      );
    }
    final next = contact.copyWith(
      phoneE164: e164,
      name: contact.name.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    return _write(
      () => _remote.updateContact(next),
      next,
      (value) {
        _cache.contacts = [
          for (final item in _cache.contacts)
            if (item.id == value.id) value else item,
        ];
      },
      keep: _keepContacts,
    );
  }

  Future<void> deleteContact(String id) async {
    await _ensure();
    final previous = [..._cache.contacts];
    _cache.contacts = _cache.contacts.where((c) => c.id != id).toList();
    if (_cache.contacts.isNotEmpty && !_cache.contacts.any((c) => c.isPrimary)) {
      _cache.contacts[0] = _cache.contacts[0].copyWith(isPrimary: true);
    }
    await _local.save(_cache);
    try {
      await _remote.deleteContact(id);
    } catch (_) {
      _cache.contacts = previous;
      await _local.save(_cache);
      rethrow;
    }
  }

  Future<List<EmergencyContact>> setPrimary(String id) async {
    await _ensure();
    final optimistic = [
      for (final item in _cache.contacts)
        item.copyWith(isPrimary: item.id == id),
    ];
    return _write(
      () => _remote.setPrimary(id),
      optimistic,
      (value) => _cache.contacts = value,
      keep: _keepContacts,
    );
  }

  Future<TripShare> startShare(String rideId, {List<String>? contactIds}) async {
    if (rideId.trim().isEmpty) {
      throw SafetyException('NO_RIDE', L10n.current.shareNoRide);
    }
    final ids = contactIds ??
        _cache.contacts.where((c) => c.shareTrips && c.isEnabled).map((c) => c.id).toList();
    final token = 'tok_${newRequestId()}';
    final now = DateTime.now().toUtc();
    final optimistic = TripShare(
      shareId: 'share_$rideId',
      rideId: rideId,
      userId: _cache.preferences.userId,
      contactIds: ids,
      startedAt: now,
      expiresAt: now.add(const Duration(hours: 6)),
      shareToken: token,
      isActive: true,
    );
    return _write(
      () => _remote.startShare(rideId, contactIds: ids),
      optimistic,
      (value) => _cache.shares[rideId] = value,
      keep: () {
        final previous = _cache.shares[rideId];
        return () => previous == null
            ? _cache.shares.remove(rideId)
            : _cache.shares[rideId] = previous;
      },
    );
  }

  Future<TripShare?> getShare(String rideId) async {
    await _ensure();
    try {
      final live = await _remote.getShare(rideId);
      if (live != null) {
        _cache.shares[rideId] = live;
        await _local.save(_cache);
      }
      return live ?? _cache.shares[rideId];
    } catch (error, stackTrace) {
      AppLog.error(
        'safety.share_refresh_failed',
        error: error,
        stackTrace: stackTrace,
        extra: {'rideId': rideId},
      );
      return _cache.shares[rideId];
    }
  }

  Future<void> stopShare(String rideId) async {
    await _ensure();
    final previous = _cache.shares[rideId];
    final current = previous?.copyWith(isActive: false);
    if (current != null) _cache.shares[rideId] = current;
    await _local.save(_cache);
    try {
      await _remote.stopShare(rideId);
    } catch (_) {
      if (previous != null) _cache.shares[rideId] = previous;
      await _local.save(_cache);
      rethrow;
    }
  }

  Future<RideCheckPolicy> patchRideCheck(bool enabled) {
    final next = _cache.rideCheck.copyWith(
      enabled: enabled,
      updatedAt: DateTime.now().toUtc(),
    );
    return _write(
      () => _remote.patchRideCheck(next),
      next,
      (value) {
        _cache.rideCheck = value;
        _cache.preferences = _cache.preferences.copyWith(rideCheckEnabled: value.enabled);
      },
      keep: () {
        final policy = _cache.rideCheck;
        final enabled = _cache.preferences.rideCheckEnabled;
        return () {
          _cache.rideCheck = policy;
          _cache.preferences =
              _cache.preferences.copyWith(rideCheckEnabled: enabled);
        };
      },
    );
  }

  Future<RideCheckEvent> postEvent(RideCheckEvent event) async {
    await _ensure();
    final existing = _cache.events.where((e) => e.eventId == event.eventId);
    if (existing.isNotEmpty) return existing.first;
    final lastResolved = _cache.events.where((e) => e.status == RideCheckStatus.resolved);
    if (lastResolved.isNotEmpty) {
      final latest = lastResolved.last.at;
      if (event.at.isBefore(latest) || event.at.isAtSameMomentAs(latest)) {
        return event.copyWith(status: RideCheckStatus.stale);
      }
    }
    return _write(
      () => _remote.postSafetyEvent(event),
      event,
      (value) {
        // rider-u197: a card closed while its open was being sent stays
        // closed, with the answers saved on this device.
        final local = _cache.events
            .where((e) => e.eventId == value.eventId)
            .lastOrNull;
        final kept = local?.status == RideCheckStatus.resolved
            ? value.copyWith(
                status: RideCheckStatus.resolved,
                payload: {...value.payload, ...local!.payload},
              )
            : value;
        _cache.events = [..._cache.events.where((e) => e.eventId != value.eventId), kept];
      },
      keep: () => _keepEvent(event.eventId),
    );
  }

  Future<List<RideCheckEvent>> refreshEvents(String rideId) async {
    if (rideId.trim().isEmpty) return const [];
    await _ensure();
    final events = await _remote.listSafetyEvents(rideId);
    _cache.events = [
      for (final event in _cache.events)
        if (event.rideId != rideId) event,
      ...events,
    ];
    await _local.save(_cache);
    return events;
  }

  Future<RideCheckEvent> respondEvent({
    required String rideId,
    required String eventId,
    required String action,
  }) async {
    final current = _cache.events.firstWhere(
      (e) => e.eventId == eventId,
      orElse: () => RideCheckEvent(
        eventId: eventId,
        rideId: rideId,
        type: RideCheckEventType.manualSafetyCheck,
        at: DateTime.now().toUtc(),
      ),
    );
    final next = current.copyWith(
      status: action == 'resolved' ? RideCheckStatus.resolved : RideCheckStatus.acknowledged,
    );
    return _write(
      () => _remote.respondSafetyEvent(rideId: rideId, eventId: eventId, action: action),
      next,
      (value) {
        _cache.events = [
          for (final item in _cache.events)
            if (item.eventId == value.eventId)
              // RC5: the answers saved on this device stay with the event
              // even when the server's copy does not echo them.
              value.copyWith(payload: {...item.payload, ...value.payload})
            else
              item,
        ];
      },
      keep: () => _keepEvent(eventId),
    );
  }

  /// The Ride check events saved on this device for [rideId], without a
  /// network call. Trip details read this, and may open before Safety has
  /// loaded.
  Future<List<RideCheckEvent>> cachedRideCheckEvents(String rideId) async {
    final id = rideId.trim();
    if (id.isEmpty) return const [];
    final source = _loaded ? _cache : await _local.load();
    return [
      for (final event in source.events)
        if (event.rideId == id && isRideCheckEvent(event)) event,
    ];
  }

  /// RC4/RC5: keeps [submission]'s answers on the trip's Ride check event
  /// on this device first, so the trip's details have them even when the
  /// server cannot be reached, then sends them with the rider, driver and
  /// trip details. A send failure is rethrown; the saved answers stay.
  Future<RideCheckReceipt> submitRideCheckAnswers(
    RideCheckSubmission submission,
  ) async {
    await keepRideCheckAnswers(submission);
    final receipt = await _remote.postRideCheckAnswers(submission);
    final alertId = receipt.alertId;
    if (alertId != null) {
      // The event as it is now: a close saved while this was sent stays
      // resolved with its own answers.
      final now = _cache.events
          .where((event) => event.eventId == submission.checkId)
          .lastOrNull;
      if (now != null) {
        _cache.events = [
          for (final event in _cache.events)
            if (event.eventId != now.eventId) event,
          now.copyWith(payload: {...now.payload, 'alertId': alertId}),
        ];
        await _local.save(_cache);
      }
    }
    return receipt;
  }

  /// [submission]'s answers on the trip's Ride check event on this device
  /// only (rider-u197: a close is saved at once, not after the sends queued
  /// before it).
  Future<void> keepRideCheckAnswers(RideCheckSubmission submission) async {
    await _ensure();
    RideCheckEvent? current;
    for (final event in _cache.events) {
      if (event.eventId == submission.checkId) current = event;
    }
    // A closed card's answers are final; an earlier send never reopens it.
    if (!submission.isFinal && current?.status == RideCheckStatus.resolved) {
      return;
    }
    final base = current ??
        RideCheckEvent(
          eventId: submission.checkId,
          rideId: submission.context.rideId,
          type: submission.trigger.eventType,
          at: submission.shownAt,
        );
    RideCheckEvent withAnswers(String? alertId) => base.copyWith(
          status: submission.isFinal
              ? RideCheckStatus.resolved
              : submission.answers.isEmpty
                  ? base.status
                  : RideCheckStatus.acknowledged,
          payload: {
            ...base.payload,
            'kind': rideCheckEventKind,
            'trigger': submission.trigger.wire,
            'reason': submission.reason.toJson(),
            'answers': [for (final a in submission.answers) a.toJson()],
            'answeredAt': DateTime.now().toUtc().toIso8601String(),
            if (alertId != null) 'alertId': alertId,
            // rider-u195: an alert was asked for. Kept on the device before
            // it is sent, so after a reload a failed alert is known as
            // failed (no alertId) rather than as no alert.
            if (submission.alert || base.payload['alertRequested'] == true)
              'alertRequested': true,
          },
        );
    void keep(RideCheckEvent next) {
      _cache.events = [
        for (final event in _cache.events)
          if (event.eventId != next.eventId) event,
        next,
      ];
    }

    final existingAlert = base.payload['alertId'];
    keep(withAnswers(
      submission.alertId ?? (existingAlert is String ? existingAlert : null),
    ));
    await _local.save(_cache);
  }

  /// RC5: a Ride check recording is kept on this device only. No server
  /// call is made for it, not even its metadata.
  Future<AudioRecording> initDeviceAudio(String rideId) async {
    await _ensure();
    final rec = AudioRecording(
      id: 'aud_${newRequestId()}',
      rideId: rideId,
      createdAt: DateTime.now().toUtc(),
      uploadStatus: AudioUploadStatus.localOnly,
      deviceOnly: true,
    );
    _cache.recordings = [..._cache.recordings, rec];
    await _local.save(_cache);
    return rec;
  }

  Future<AudioRecording> completeDeviceAudio(AudioRecording recording) async {
    await _ensure();
    final next = recording.copyWith(
      endedAt: recording.endedAt ?? DateTime.now().toUtc(),
      uploadStatus: AudioUploadStatus.localOnly,
    );
    _cache.recordings = [
      for (final item in _cache.recordings)
        if (item.id == next.id) next else item,
    ];
    await _local.save(_cache);
    return next;
  }

  Future<AudioRecording> initAudio(String rideId) {
    final rec = AudioRecording(
      id: 'aud_${newRequestId()}',
      rideId: rideId,
      createdAt: DateTime.now().toUtc(),
      uploadStatus: AudioUploadStatus.localOnly,
    );
    return _write(
      () => _remote.initAudio(rideId: rideId),
      rec,
      (value) {
        _cache.recordings = [..._cache.recordings.where((r) => r.id != value.id), value];
      },
      keep: () => _keepRecording(rec.id),
    );
  }

  Future<AudioRecording> completeAudio(AudioRecording recording) {
    final next = recording.copyWith(
      endedAt: DateTime.now().toUtc(),
      uploadStatus: AudioUploadStatus.localOnly,
    );
    return _write(
      () => _remote.completeAudio(
        rideId: recording.rideId ?? '',
        recordingId: recording.id,
        durationMs: recording.durationMs,
      ),
      next,
      (value) {
        // Completion confirms metadata, not the private file on this device.
        final local = value.copyWith(
          localPath: recording.localPath,
          durationMs: recording.durationMs,
          endedAt: recording.endedAt,
        );
        _cache.recordings = [
          for (final item in _cache.recordings)
            if (item.id == value.id) local else item,
        ];
      },
      keep: () => _keepRecording(recording.id),
    ).then((value) => value.copyWith(
          localPath: recording.localPath,
          durationMs: recording.durationMs,
          endedAt: recording.endedAt,
        ));
  }

  Future<void> deleteAudio(AudioRecording recording) async {
    await _ensure();
    _cache.recordings = _cache.recordings.where((r) => r.id != recording.id).toList();
    await _local.save(_cache);
    if (recording.rideId != null && !recording.deviceOnly) {
      await _remote.deleteAudio(rideId: recording.rideId!, recordingId: recording.id);
    }
  }
}

class RidePinRepository {
  RidePinRepository({SafetyStore? store}) : _store = store ?? SafetyStore.shared;
  final SafetyStore _store;
  RidePin current() => _store.pin;
  Future<RidePin> rotate({String? idempotencyKey}) =>
      _store.rotatePin(idempotencyKey: idempotencyKey);
}

class EmergencyContactsRepository {
  EmergencyContactsRepository({SafetyStore? store})
      : _store = store ?? SafetyStore.shared;
  final SafetyStore _store;
  List<EmergencyContact> listContacts() => _store.contacts;
  Future<EmergencyContact> createContact({
    required String name,
    required String phone,
    String relationship = 'Other',
    bool shareTrips = false,
    bool isEnabled = true,
    String? idempotencyKey,
  }) =>
      _store.createContact(
        name: name,
        phone: phone,
        relationship: relationship,
        shareTrips: shareTrips,
        isEnabled: isEnabled,
        idempotencyKey: idempotencyKey,
      );
  Future<EmergencyContact> updateContact(EmergencyContact contact) =>
      _store.updateContact(contact);
  Future<void> deleteContact(String id) => _store.deleteContact(id);
  Future<List<EmergencyContact>> setPrimaryContact(String id) =>
      _store.setPrimary(id);
}

class TripShareRepository {
  TripShareRepository({SafetyStore? store}) : _store = store ?? SafetyStore.shared;
  final SafetyStore _store;
  Future<TripShare> start(String rideId, {List<String>? contactIds}) =>
      _store.startShare(rideId, contactIds: contactIds);
  Future<TripShare?> get(String rideId) => _store.getShare(rideId);
  Future<void> stop(String rideId) => _store.stopShare(rideId);
}

class RideCheckRepository {
  RideCheckRepository({SafetyStore? store}) : _store = store ?? SafetyStore.shared;
  final SafetyStore _store;
  RideCheckPolicy policy() => _store.rideCheck;
  List<RideCheckEvent> events() => _store.rideCheckEvents;
  Future<RideCheckPolicy> setEnabled(bool enabled) => _store.patchRideCheck(enabled);
  Future<RideCheckEvent> post(RideCheckEvent event) => _store.postEvent(event);
  Future<RideCheckEvent> respond({
    required String rideId,
    required String eventId,
    required String action,
  }) =>
      _store.respondEvent(rideId: rideId, eventId: eventId, action: action);
}
