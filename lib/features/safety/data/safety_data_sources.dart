import 'dart:convert';

import 'package:movera_rider/core/api/api_client.dart';
import 'package:movera_rider/core/api/idempotency.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/features/safety/data/secure_ride_pin_store.dart';
import 'package:movera_rider/features/safety/domain/audio_recording.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_check_record.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:movera_rider/features/safety/domain/trip_share.dart';
import 'package:movera_rider/core/logging/app_log.dart';

class SafetyCache {
  SafetyCache({
    SafetyPreferences? preferences,
    RidePin? pin,
    List<EmergencyContact>? contacts,
    Map<String, TripShare>? shares,
    RideCheckPolicy? rideCheck,
    List<RideCheckEvent>? events,
    List<AudioRecording>? recordings,
  }) : preferences = preferences ?? const SafetyPreferences(),
       pin = pin ?? RidePin.unavailable,
       contacts = contacts ?? <EmergencyContact>[],
       shares = shares ?? <String, TripShare>{},
       rideCheck = rideCheck ?? const RideCheckPolicy(),
       events = events ?? <RideCheckEvent>[],
       recordings = recordings ?? <AudioRecording>[];

  SafetyPreferences preferences;
  RidePin pin;
  List<EmergencyContact> contacts;
  Map<String, TripShare> shares;
  RideCheckPolicy rideCheck;
  List<RideCheckEvent> events;
  List<AudioRecording> recordings;

  Map<String, dynamic> toJson() => {
    'preferences': preferences.toJson(),
    'pin': pin.toJson(),
    'contacts': contacts.map((c) => c.toJson()).toList(),
    'shares': shares.map((key, value) => MapEntry(key, value.toJson())),
    'rideCheck': rideCheck.toJson(),
    'events': events.map((e) => e.toJson()).toList(),
    'recordings': recordings.map((r) => r.toJson()).toList(),
  };

  factory SafetyCache.fromJson(Map<String, dynamic>? json) {
    if (json == null) return SafetyCache();
    final contacts = <EmergencyContact>[];
    final rawContacts = json['contacts'];
    if (rawContacts is List) {
      for (final item in rawContacts) {
        if (item is Map) {
          contacts.add(
            EmergencyContact.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final shares = <String, TripShare>{};
    final rawShares = json['shares'];
    if (rawShares is Map) {
      rawShares.forEach((key, value) {
        if (value is Map) {
          shares['$key'] = TripShare.fromJson(Map<String, dynamic>.from(value));
        }
      });
    }
    final events = <RideCheckEvent>[];
    final rawEvents = json['events'];
    if (rawEvents is List) {
      for (final item in rawEvents) {
        if (item is Map) {
          events.add(RideCheckEvent.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final recordings = <AudioRecording>[];
    final rawRec = json['recordings'];
    if (rawRec is List) {
      for (final item in rawRec) {
        if (item is Map) {
          recordings.add(
            AudioRecording.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return SafetyCache(
      preferences: SafetyPreferences.fromJson(
        json['preferences'] is Map
            ? Map<String, dynamic>.from(json['preferences'] as Map)
            : null,
      ),
      pin: RidePin.fromJson(
        json['pin'] is Map
            ? Map<String, dynamic>.from(json['pin'] as Map)
            : null,
      ),
      contacts: contacts,
      shares: shares,
      rideCheck: RideCheckPolicy.fromJson(
        json['rideCheck'] is Map
            ? Map<String, dynamic>.from(json['rideCheck'] as Map)
            : null,
      ),
      events: events,
      recordings: recordings,
    );
  }
}

abstract class SafetyLocalDataSource {
  Future<SafetyCache> load();
  Future<void> save(SafetyCache cache);
}

class PreferencesSafetyLocalDataSource implements SafetyLocalDataSource {
  PreferencesSafetyLocalDataSource({
    this.memoryOnly = false,
    SecureRidePinStore? pinStore,
  }) : _pinStore = pinStore ?? const SecureRidePinStore();

  static const cacheKey = 'movera_safety_cache_v1';
  static const _pinPlaceholder = '0000';
  final bool memoryOnly;
  final SecureRidePinStore _pinStore;
  SafetyCache _memory = SafetyCache();
  bool _seeded = false;

  @override
  Future<SafetyCache> load() async {
    if (memoryOnly) {
      if (!_seeded) {
        _memory = SafetyCache();
        _seeded = true;
      }
      return _copy(_memory);
    }
    try {
      final prefs = await PreferencesStore.load();
      final raw = prefs.getString(cacheKey);
      SafetyCache cache;
      if (raw == null || raw.isEmpty) {
        cache = SafetyCache();
      } else {
        cache = SafetyCache.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
      // On iOS/Android the PIN digits live in Keychain/Keystore and on web
      // in memory only (P-06) — never in this plaintext prefs blob. A legacy
      // blob that still carries real digits is adopted and then scrubbed by
      // the _persist below. Desktop/tests keep the PIN embedded as before.
      if (_pinStore.keepsPinOutOfPreferences) {
        final securePin = await _pinStore.read();
        if (securePin != null) {
          cache.pin = cache.pin.copyWith(pin: securePin);
        } else if (cache.pin.isAvailable && cache.pin.pin != _pinPlaceholder) {
          // First run on this store, or migrating an older plaintext cache
          // that still carries a real PIN: adopt it into secure storage.
          await _pinStore.write(cache.pin.pin);
        } else {
          cache.pin = cache.pin.copyWith(pin: '');
        }
      }
      _memory = cache;
      await _persist(cache, prefs: prefs, raw: raw);
      return _copy(_memory);
    } catch (_) {
      if (!_seeded) {
        _memory = SafetyCache();
        _seeded = true;
      }
      return _copy(_memory);
    }
  }

  @override
  Future<void> save(SafetyCache cache) async {
    _memory = _copy(cache);
    if (memoryOnly) return;
    if (_pinStore.keepsPinOutOfPreferences) {
      if (cache.pin.isAvailable) await _pinStore.write(cache.pin.pin);
    }
    try {
      await _persist(cache);
    } catch (error) {
      AppLog.warning('safety.persist_failed', extra: {'error': '$error'});
    }
  }

  Future<void> _persist(
    SafetyCache cache, {
    PreferencesStore? prefs,
    String? raw,
  }) async {
    final store = prefs ?? await PreferencesStore.load();
    if (_pinStore.keepsPinOutOfPreferences) {
      final scrubbed = _copy(cache)
        ..pin = cache.pin.copyWith(pin: _pinPlaceholder);
      await store.setString(cacheKey, jsonEncode(scrubbed.toJson()));
    } else if (raw == null || raw.isEmpty) {
      // Only re-write on a fresh/empty cache load; save() always persists.
      await store.setString(cacheKey, jsonEncode(cache.toJson()));
    }
  }

  SafetyCache _copy(SafetyCache cache) => SafetyCache.fromJson(cache.toJson());
}

abstract class SafetyRemoteDataSource {
  Future<SafetyPreferences> getPreferences();
  Future<SafetyPreferences> patchPreferences(
    SafetyPreferences next, {
    String? idempotencyKey,
  });
  Future<RidePin> getPin();
  Future<RidePin> rotatePin({String? idempotencyKey});
  Future<List<EmergencyContact>> listContacts();
  Future<EmergencyContact> createContact(
    EmergencyContact contact, {
    String? idempotencyKey,
  });
  Future<EmergencyContact> updateContact(EmergencyContact contact);
  Future<void> deleteContact(String id);
  Future<List<EmergencyContact>> setPrimary(String id);
  Future<TripShare> startShare(
    String rideId, {
    List<String>? contactIds,
    String? idempotencyKey,
  });
  Future<TripShare?> getShare(String rideId);
  Future<TripShare> patchShare(String rideId, TripShare share);
  Future<void> stopShare(String rideId);
  Future<RideCheckPolicy> getRideCheck();
  Future<RideCheckPolicy> patchRideCheck(RideCheckPolicy policy);
  Future<RideCheckEvent> postSafetyEvent(
    RideCheckEvent event, {
    String? idempotencyKey,
  });
  Future<List<RideCheckEvent>> listSafetyEvents(String rideId);
  Future<RideCheckEvent> respondSafetyEvent({
    required String rideId,
    required String eventId,
    required String action,
  });

  /// RC4: the rider's Ride check answers, with rider, driver and trip
  /// details. Alerts the Movera safety team when [submission] says so.
  Future<RideCheckReceipt> postRideCheckAnswers(
    RideCheckSubmission submission, {
    String? idempotencyKey,
  });
  Future<AudioRecording> initAudio({
    required String rideId,
    String? idempotencyKey,
  });
  Future<AudioRecording> completeAudio({
    required String rideId,
    required String recordingId,
    required int durationMs,
  });
  Future<void> deleteAudio({
    required String rideId,
    required String recordingId,
  });
}

class ApiSafetyRemoteDataSource implements SafetyRemoteDataSource {
  ApiSafetyRemoteDataSource(this._api);
  final ApiClient _api;

  @override
  Future<SafetyPreferences> getPreferences() async {
    final json = await _api.get('/api/v1/safety/preferences');
    return SafetyPreferences.fromJson(_map(json['preferences'] ?? json));
  }

  @override
  Future<SafetyPreferences> patchPreferences(
    SafetyPreferences next, {
    String? idempotencyKey,
  }) async {
    final json = await _api.patch(
      '/api/v1/safety/preferences',
      body: next.toJson(),
      idempotencyKey: idempotencyKey ?? newIdempotencyKey('safety-prefs'),
    );
    return SafetyPreferences.fromJson(_map(json['preferences'] ?? json));
  }

  @override
  Future<RidePin> getPin() async {
    final json = await _api.get('/api/v1/safety/pin');
    return RidePin.fromJson(_map(json['pin'] ?? json));
  }

  @override
  Future<RidePin> rotatePin({String? idempotencyKey}) async {
    final json = await _api.post(
      '/api/v1/safety/pin/rotate',
      idempotencyKey: idempotencyKey ?? newIdempotencyKey('safety-pin'),
    );
    return RidePin.fromJson(_map(json['pin'] ?? json));
  }

  @override
  Future<List<EmergencyContact>> listContacts() async {
    final json = await _api.get('/api/v1/safety/contacts');
    return _contacts(json['contacts']);
  }

  @override
  Future<EmergencyContact> createContact(
    EmergencyContact contact, {
    String? idempotencyKey,
  }) async {
    final json = await _api.post(
      '/api/v1/safety/contacts',
      body: contact.toJson(),
      idempotencyKey: idempotencyKey ?? newIdempotencyKey('safety-contact'),
    );
    return EmergencyContact.fromJson(_map(json['contact'] ?? json));
  }

  @override
  Future<EmergencyContact> updateContact(EmergencyContact contact) async {
    final json = await _api.patch(
      '/api/v1/safety/contacts/${contact.id}',
      body: contact.toJson(),
      idempotencyKey: newIdempotencyKey('safety-contact-update'),
    );
    return EmergencyContact.fromJson(_map(json['contact'] ?? json));
  }

  @override
  Future<void> deleteContact(String id) async {
    await _api.delete('/api/v1/safety/contacts/$id');
  }

  @override
  Future<List<EmergencyContact>> setPrimary(String id) async {
    final json = await _api.post(
      '/api/v1/safety/contacts/$id/primary',
      idempotencyKey: newIdempotencyKey('safety-primary'),
    );
    return _contacts(json['contacts']);
  }

  @override
  Future<TripShare> startShare(
    String rideId, {
    List<String>? contactIds,
    String? idempotencyKey,
  }) async {
    final json = await _api.post(
      '/api/v1/rides/$rideId/share',
      body: {'contactIds': contactIds ?? []},
      idempotencyKey: idempotencyKey ?? newIdempotencyKey('safety-share'),
    );
    return TripShare.fromJson(_map(json['share'] ?? json));
  }

  @override
  Future<TripShare?> getShare(String rideId) async {
    try {
      final json = await _api.get('/api/v1/rides/$rideId/share');
      final share = json['share'];
      if (share is Map) {
        return TripShare.fromJson(Map<String, dynamic>.from(share));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TripShare> patchShare(String rideId, TripShare share) async {
    final json = await _api.patch(
      '/api/v1/rides/$rideId/share',
      body: share.toJson(),
    );
    return TripShare.fromJson(_map(json['share'] ?? json));
  }

  @override
  Future<void> stopShare(String rideId) async {
    await _api.delete('/api/v1/rides/$rideId/share');
  }

  @override
  Future<RideCheckPolicy> getRideCheck() async {
    final json = await _api.get('/api/v1/safety/ridecheck/preferences');
    return RideCheckPolicy.fromJson(_map(json['policy'] ?? json));
  }

  @override
  Future<RideCheckPolicy> patchRideCheck(RideCheckPolicy policy) async {
    final json = await _api.patch(
      '/api/v1/safety/ridecheck/preferences',
      body: policy.toJson(),
      idempotencyKey: newIdempotencyKey('safety-ridecheck'),
    );
    return RideCheckPolicy.fromJson(_map(json['policy'] ?? json));
  }

  @override
  Future<RideCheckEvent> postSafetyEvent(
    RideCheckEvent event, {
    String? idempotencyKey,
  }) async {
    final json = await _api.post(
      '/api/v1/rides/${event.rideId}/safety-events',
      body: event.toJson(),
      idempotencyKey: idempotencyKey ?? newIdempotencyKey('safety-event'),
    );
    return RideCheckEvent.fromJson(_map(json['event'] ?? json));
  }

  @override
  Future<List<RideCheckEvent>> listSafetyEvents(String rideId) async {
    final json = await _api.get('/api/v1/rides/$rideId/safety-events');
    final raw = json['events'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => RideCheckEvent.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<RideCheckEvent> respondSafetyEvent({
    required String rideId,
    required String eventId,
    required String action,
  }) async {
    final json = await _api.post(
      '/api/v1/rides/$rideId/safety-events/$eventId/respond',
      body: {'action': action},
      idempotencyKey: newIdempotencyKey('safety-respond'),
    );
    return RideCheckEvent.fromJson(_map(json['event'] ?? json));
  }

  @override
  Future<RideCheckReceipt> postRideCheckAnswers(
    RideCheckSubmission submission, {
    String? idempotencyKey,
  }) async {
    final json = await _api.post(
      '/api/v1/safety/ridecheck/answers',
      body: submission.toJson(),
      idempotencyKey:
          idempotencyKey ?? newIdempotencyKey('safety-ridecheck-answers'),
    );
    return RideCheckReceipt.fromJson(json);
  }

  @override
  Future<AudioRecording> initAudio({
    required String rideId,
    String? idempotencyKey,
  }) async {
    final json = await _api.post(
      '/api/v1/rides/$rideId/safety-audio/init',
      idempotencyKey: idempotencyKey ?? newIdempotencyKey('safety-audio'),
    );
    return AudioRecording.fromJson(_map(json['recording'] ?? json));
  }

  @override
  Future<AudioRecording> completeAudio({
    required String rideId,
    required String recordingId,
    required int durationMs,
  }) async {
    final json = await _api.post(
      '/api/v1/rides/$rideId/safety-audio/$recordingId/complete',
      body: {'durationMs': durationMs},
    );
    return AudioRecording.fromJson(_map(json['recording'] ?? json));
  }

  @override
  Future<void> deleteAudio({
    required String rideId,
    required String recordingId,
  }) async {
    await _api.delete('/api/v1/rides/$rideId/safety-audio/$recordingId');
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<EmergencyContact> _contacts(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => EmergencyContact.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}
