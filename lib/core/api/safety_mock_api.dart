import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';

/// In-process Safety mock. Same paths/DTOs the real API will use.
class SafetyMockApi {
  /// FLOW-9: the demo build has no server, so the mock keeps the rider's
  /// Safety settings, PIN and trusted contacts here between launches; a
  /// reload used to wipe them. `movera_` prefixed, so sign-out removes it.
  static const storageKey = 'movera_safety_demo_v1';

  /// Contract error body for an unknown id (R-O4: lower-case codes).
  static const _notFound = <String, dynamic>{
    'code': 'not_found',
    'message': 'not_found',
    'retryable': false,
  };

  bool _restored = false;

  /// Bumped by [reset]; a restore or save that started before a sign-out
  /// must not bring the previous rider's data back afterwards.
  int _generation = 0;

  /// Sign-out (UserDataWipe): forget the previous rider's settings, PIN,
  /// contacts, shares, events and recordings in memory. The next request
  /// starts from defaults with a new PIN.
  void reset() {
    _generation++;
    _restored = false;
    preferences
      ..clear()
      ..addAll(_defaultPreferences());
    pin = _newPin(required: false);
    contacts.clear();
    shares.clear();
    rideCheck = _defaultRideCheck();
    events.clear();
    recordings.clear();
    rideCheckAnswers.clear();
    rideCheckAlerts.clear();
    lastLoggedPin = null;
  }

  /// Loads what an earlier launch saved. Runs once per mock instance.
  Future<void> restoreOnce() async {
    if (_restored) return;
    _restored = true;
    final generation = _generation;
    try {
      final prefs = await PreferencesStore.load();
      if (generation != _generation) return;
      final raw = prefs.getString(storageKey);
      if (raw == null) {
        // First launch: keep this PIN, so it no longer changes per launch.
        await persist();
        return;
      }
      final saved = jsonDecode(raw);
      if (saved is! Map) return;
      final prefsMap = saved['preferences'];
      if (prefsMap is Map)
        preferences.addAll(Map<String, dynamic>.from(prefsMap));
      final pinMap = saved['pin'];
      if (pinMap is Map) pin = Map<String, dynamic>.from(pinMap);
      final rideCheckMap = saved['rideCheck'];
      if (rideCheckMap is Map) {
        rideCheck = Map<String, dynamic>.from(rideCheckMap);
      }
      final list = saved['contacts'];
      if (list is List) {
        contacts
          ..clear()
          ..addAll(list.whereType<Map>().map(Map<String, dynamic>.from));
      }
    } catch (error) {
      AppLog.warning('safety.mock_restore_failed', extra: {'error': '$error'});
    }
  }

  /// Saves the settings, PIN and contacts for the next launch.
  Future<void> persist() async {
    final generation = _generation;
    try {
      final prefs = await PreferencesStore.load();
      if (generation != _generation) return;
      await prefs.setString(
        storageKey,
        jsonEncode({
          'preferences': preferences,
          'pin': pin,
          'rideCheck': rideCheck,
          'contacts': contacts,
        }),
      );
    } catch (error) {
      AppLog.warning('safety.mock_persist_failed', extra: {'error': '$error'});
    }
  }

  final Map<String, dynamic> preferences = _defaultPreferences();

  static Map<String, dynamic> _defaultPreferences() => {
    'userId': 'rider-local',
    'pinRequired': false,
    'tripShareEnabled': false,
    'tripShareMode': 'manual',
    'tripShareContactIds': <String>[],
    'rideCheckEnabled': true,
    'version': 1,
  };

  Map<String, dynamic> pin = _newPin(required: false);
  final List<Map<String, dynamic>> contacts = [];
  final Map<String, Map<String, dynamic>> shares = {};
  Map<String, dynamic> rideCheck = _defaultRideCheck();

  static Map<String, dynamic> _defaultRideCheck() => {
    'enabled': true,
    'userId': 'rider-local',
    'triggers': defaultRideCheckTriggers(),
  };

  /// Ride check triggers as admin sets them in Dispatch › Safety (RC6), with
  /// the app's defaults. The rider app reads them and cannot change them.
  static Map<String, dynamic> defaultRideCheckTriggers() => {
    // Admin's "Finished far from drop-off" (X km) and "Unexpected long
    // stop" (Y min).
    'finishFarFromDropoffKm': 3,
    'longStopMinutes': 2,
    'droppedFar': {'enabled': true, 'km': 3},
    'longStop': {'enabled': true, 'minutes': 5},
    'offRoute': {'enabled': true, 'km': 2, 'longerPercent': 50},
    'possibleCrash': {'enabled': true},
  };

  Map<String, dynamic> _rideCheckPolicy() => {
    ...rideCheck,
    'triggers': rideCheck['triggers'] is Map
        ? rideCheck['triggers']
        : defaultRideCheckTriggers(),
  };

  final List<Map<String, dynamic>> events = [];
  final List<Map<String, dynamic>> recordings = [];

  /// RC4: every Ride check answer received, latest per check, as admin's
  /// Ride check log would keep them.
  final List<Map<String, dynamic>> rideCheckAnswers = [];

  /// RC4: alerts sent to admin and Dispatch, by alert id.
  final Map<String, Map<String, dynamic>> rideCheckAlerts = {};
  String? lastLoggedPin;

  /// rider-u16: where new PINs come from. Before, the PIN was the clock's
  /// microseconds mod 10000; on the web DateTime.now() has millisecond
  /// precision, so every demo PIN ended in 000 (ten possible values).
  @visibleForTesting
  static Random pinRandom = Random.secure();

  static Map<String, dynamic> _newPin({required bool required}) {
    final now = DateTime.now().toUtc();
    final n = pinRandom.nextInt(10000);
    return {
      'pinId': 'pin_${now.microsecondsSinceEpoch}',
      'userId': 'rider-local',
      'pin': n.toString().padLeft(4, '0'),
      'required': required,
      'rotatedAt': now.toIso8601String(),
      'version': 1,
      'serverAuthoritative': false,
    };
  }

  /// Returns null if the path is not a Safety route.
  ({int status, Map<String, dynamic> payload})? handle({
    required String method,
    required String path,
    required Map<String, dynamic> body,
    required String requestId,
  }) {
    if (path == '/api/v1/safety/preferences' && method == 'GET') {
      return (status: 200, payload: {'code': 'OK', 'preferences': preferences});
    }
    if (path == '/api/v1/safety/preferences' && method == 'PATCH') {
      preferences.addAll({
        if (body.containsKey('pinRequired'))
          'pinRequired': body['pinRequired'] == true,
        if (body.containsKey('tripShareEnabled'))
          'tripShareEnabled': body['tripShareEnabled'] == true,
        if (body.containsKey('tripShareMode'))
          'tripShareMode': '${body['tripShareMode']}',
        if (body['tripShareContactIds'] is List)
          'tripShareContactIds': List<String>.from(
            (body['tripShareContactIds'] as List).map((e) => '$e'),
          ),
        if (body.containsKey('rideCheckEnabled'))
          'rideCheckEnabled': body['rideCheckEnabled'] == true,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      pin['required'] = preferences['pinRequired'] == true;
      rideCheck['enabled'] = preferences['rideCheckEnabled'] != false;
      return (status: 200, payload: {'code': 'OK', 'preferences': preferences});
    }
    if (path == '/api/v1/safety/pin' && method == 'GET') {
      return (status: 200, payload: {'code': 'OK', 'pin': pin});
    }
    if (path == '/api/v1/safety/pin/rotate' && method == 'POST') {
      pin = _newPin(required: preferences['pinRequired'] == true);
      lastLoggedPin = null;
      return (status: 200, payload: {'code': 'OK', 'pin': pin});
    }
    // ARCH-22: PIN verification is the driver app's call
    // (docs/ride-pin-backend-contract.md section 3); the rider never verifies.
    if (path == '/api/v1/safety/contacts' && method == 'GET') {
      return (status: 200, payload: {'code': 'OK', 'contacts': contacts});
    }
    if (path == '/api/v1/safety/contacts' && method == 'POST') {
      if (contacts.length >= 5) {
        return (
          status: 409,
          payload: {
            'code': 'conflict',
            'reason': 'contact_limit',
            'message': 'Max 5 contacts',
            'retryable': false,
          },
        );
      }
      final created = Map<String, dynamic>.from(body);
      created['id'] = created['id'] ?? 'ec_$requestId';
      created['userId'] = created['userId'] ?? 'rider-local';
      created['createdAt'] =
          created['createdAt'] ?? DateTime.now().toUtc().toIso8601String();
      if (contacts.isEmpty) created['isPrimary'] = true;
      contacts.add(created);
      return (status: 200, payload: {'code': 'OK', 'contact': created});
    }
    final contactId = RegExp(r'^/api/v1/safety/contacts/([^/]+)$')
        .firstMatch(path);
    if (contactId != null && method == 'PATCH') {
      final id = contactId.group(1);
      final index = contacts.indexWhere((c) => c['id'] == id);
      if (index < 0) {
        return (status: 404, payload: _notFound);
      }
      contacts[index] = {...contacts[index], ...body, 'id': id};
      return (status: 200, payload: {'code': 'OK', 'contact': contacts[index]});
    }
    if (contactId != null && method == 'DELETE') {
      final id = contactId.group(1);
      contacts.removeWhere((c) => c['id'] == id);
      if (contacts.isNotEmpty && !contacts.any((c) => c['isPrimary'] == true)) {
        contacts[0]['isPrimary'] = true;
      }
      return (status: 200, payload: {'code': 'OK'});
    }
    final primary = RegExp(r'^/api/v1/safety/contacts/([^/]+)/primary$')
        .firstMatch(path);
    if (primary != null && method == 'POST') {
      final id = primary.group(1);
      for (final contact in contacts) {
        contact['isPrimary'] = contact['id'] == id;
      }
      return (status: 200, payload: {'code': 'OK', 'contacts': contacts});
    }
    final share = RegExp(r'^/api/v1/rides/([^/]+)/share$').firstMatch(path);
    if (share != null) {
      final rideId = share.group(1)!;
      if (method == 'POST') {
        final now = DateTime.now().toUtc();
        final token = 'tok_$requestId';
        final row = {
          'shareId': 'share_$rideId',
          'rideId': rideId,
          'userId': 'rider-local',
          'contactIds': body['contactIds'] ?? [],
          'startedAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(hours: 6)).toIso8601String(),
          'shareToken': token,
          'isActive': true,
          'serverAuthoritative': true,
        };
        shares[rideId] = row;
        return (status: 200, payload: {'code': 'OK', 'share': row});
      }
      if (method == 'GET') {
        final row = shares[rideId];
        if (row == null) {
          return (status: 404, payload: _notFound);
        }
        return (status: 200, payload: {'code': 'OK', 'share': row});
      }
      if (method == 'PATCH') {
        final row = {...?shares[rideId], ...body, 'rideId': rideId};
        shares[rideId] = row;
        return (status: 200, payload: {'code': 'OK', 'share': row});
      }
      if (method == 'DELETE') {
        final row = shares[rideId];
        if (row != null) {
          row['isActive'] = false;
        }
        return (status: 200, payload: {'code': 'OK'});
      }
    }
    if (path == '/api/v1/safety/ridecheck/preferences' && method == 'GET') {
      return (
        status: 200,
        payload: {'code': 'OK', 'policy': _rideCheckPolicy()},
      );
    }
    if (path == '/api/v1/safety/ridecheck/preferences' && method == 'PATCH') {
      // The rider's switch only; the triggers are admin's.
      rideCheck = {
        ...rideCheck,
        'enabled': body['enabled'] == true,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
      preferences['rideCheckEnabled'] = rideCheck['enabled'] == true;
      return (
        status: 200,
        payload: {'code': 'OK', 'policy': _rideCheckPolicy()},
      );
    }
    if (path == '/api/v1/safety/ridecheck/answers' && method == 'POST') {
      return _rideCheckAnswer(body, requestId);
    }
    final safetyEvents = RegExp(r'^/api/v1/rides/([^/]+)/safety-events$')
        .firstMatch(path);
    if (safetyEvents != null && method == 'POST') {
      final rideId = safetyEvents.group(1)!;
      final event = {
        ...body,
        'eventId': body['eventId'] ?? 'ev_$requestId',
        'rideId': rideId,
        'status': body['status'] ?? 'pending',
        'at': body['at'] ?? DateTime.now().toUtc().toIso8601String(),
        'serverAuthoritative': true,
      };
      if (events.any((e) => e['eventId'] == event['eventId'])) {
        return (
          status: 200,
          payload: {
            'code': 'OK',
            'event': events.firstWhere(
              (e) => e['eventId'] == event['eventId'],
              orElse: () => event,
            ),
          },
        );
      }
      events.add(event);
      return (status: 200, payload: {'code': 'OK', 'event': event});
    }
    if (safetyEvents != null && method == 'GET') {
      final rideId = safetyEvents.group(1);
      final list = events.where((e) => e['rideId'] == rideId).toList();
      return (status: 200, payload: {'code': 'OK', 'events': list});
    }
    final respond = RegExp(
      r'^/api/v1/rides/([^/]+)/safety-events/([^/]+)/respond$',
    ).firstMatch(path);
    if (respond != null && method == 'POST') {
      final eventId = respond.group(2);
      final index = events.indexWhere((e) => e['eventId'] == eventId);
      if (index < 0) {
        return (status: 404, payload: _notFound);
      }
      final action = '${body['action'] ?? 'acknowledged'}';
      events[index]['status'] = action == 'resolved'
          ? 'resolved'
          : 'acknowledged';
      return (status: 200, payload: {'code': 'OK', 'event': events[index]});
    }
    final audioInit = RegExp(r'^/api/v1/rides/([^/]+)/safety-audio/init$')
        .firstMatch(path);
    if (audioInit != null && method == 'POST') {
      final rec = {
        'id': 'aud_$requestId',
        'rideId': audioInit.group(1),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'uploadStatus': 'localOnly',
        'encryptionState': 'local',
        'durationMs': 0,
      };
      recordings.add(rec);
      return (status: 200, payload: {'code': 'OK', 'recording': rec});
    }
    final audio = RegExp(
      r'^/api/v1/rides/([^/]+)/safety-audio/([^/]+)(/complete)?$',
    ).firstMatch(path);
    if (audio != null) {
      final recordingId = audio.group(2);
      final complete = audio.group(3) != null;
      final index = recordings.indexWhere((r) => r['id'] == recordingId);
      if (method == 'POST' && complete) {
        if (index < 0) {
          return (status: 404, payload: _notFound);
        }
        recordings[index]['endedAt'] = DateTime.now().toUtc().toIso8601String();
        recordings[index]['durationMs'] = body['durationMs'] ?? 0;
        recordings[index]['uploadStatus'] = 'localOnly';
        return (
          status: 200,
          payload: {'code': 'OK', 'recording': recordings[index]},
        );
      }
      if (method == 'DELETE') {
        recordings.removeWhere((r) => r['id'] == recordingId);
        return (status: 200, payload: {'code': 'OK'});
      }
    }
    return null;
  }
}

extension on SafetyMockApi {
  /// RC4: stores the answers and, when they call for it, sends the alert to
  /// admin and Dispatch with the rider, driver and trip details. A later
  /// "Yes" or "Not sure" for the same check updates that alert.
  ({int status, Map<String, dynamic> payload}) _rideCheckAnswer(
    Map<String, dynamic> body,
    String requestId,
  ) {
    final checkId = '${body['checkId'] ?? ''}'.trim();
    final rideId = '${body['rideId'] ?? ''}'.trim();
    if (checkId.isEmpty || rideId.isEmpty || body['answers'] is! List) {
      return (
        status: 422,
        payload: {
          'code': 'invalid_request',
          'reason': 'invalid_ridecheck_answer',
          'message': 'invalid_ridecheck_answer',
          'requestId': requestId,
          'retryable': false,
        },
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final record = <String, dynamic>{
      'checkId': checkId,
      'rideId': rideId,
      'trigger': body['trigger'],
      'shownAt': body['shownAt'],
      'reason': body['reason'] ?? const {},
      'answers': body['answers'],
      'final': body['final'] == true,
      'rider': body['rider'] ?? const {},
      'driver': body['driver'] ?? const {},
      'trip': body['trip'] ?? const {},
      'receivedAt': now,
    };
    rideCheckAnswers
      ..removeWhere((row) => row['checkId'] == checkId)
      ..add(record);
    // The ride's safety event carries the answers too.
    final event = events.where((e) => e['eventId'] == checkId).firstOrNull;
    if (event != null) {
      event['payload'] = {
        ...?(event['payload'] as Map?)?.cast<String, dynamic>(),
        'answers': body['answers'],
      };
    }
    Map<String, dynamic>? alert;
    final existing = rideCheckAlerts.values.where(
      (row) => row['checkId'] == checkId,
    );
    if (body['alert'] == true || existing.isNotEmpty) {
      final current = existing.isEmpty ? null : existing.first;
      final alertId = current?['alertId'] as String? ?? 'rca_$requestId';
      alert = {
        'alertId': alertId,
        'checkId': checkId,
        'rideId': rideId,
        'status': current == null ? 'sent' : 'updated',
        'recipients': const ['admin', 'dispatch'],
        'sentAt': current?['sentAt'] ?? now,
        'updatedAt': now,
        'updates': ((current?['updates'] as int?) ?? -1) + 1,
        'answers': body['answers'],
        'rider': record['rider'],
        'driver': record['driver'],
        'trip': record['trip'],
      };
      rideCheckAlerts[alertId] = alert;
      record['alertId'] = alertId;
      if (event != null) {
        event['payload'] = {
          ...?(event['payload'] as Map?)?.cast<String, dynamic>(),
          'alertId': alertId,
        };
      }
    }
    return (
      status: 200,
      payload: {
        'code': 'OK',
        'answer': record,
        'alert': ?alert,
        'requestId': requestId,
      },
    );
  }
}

SafetyMockApi? _processSafety;
SafetyMockApi safetyMockForProcess() => _processSafety ??= SafetyMockApi();
void resetSafetyMockForProcess() => _processSafety = null;
