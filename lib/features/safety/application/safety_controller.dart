import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/debug/web_qa_hooks.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/safety/application/emergency_call_service.dart';
import 'package:movera_rider/features/safety/application/ride_check_controller.dart';
import 'package:movera_rider/features/safety/application/ride_check_service.dart';
import 'package:movera_rider/features/safety/application/safety_audio_service.dart';
import 'package:movera_rider/features/safety/data/safety_repository.dart';
import 'package:movera_rider/features/safety/data/safety_store.dart';
import 'package:movera_rider/features/safety/domain/emergency_contact.dart';
import 'package:movera_rider/features/safety/domain/ride_check.dart';
import 'package:movera_rider/features/safety/domain/ride_pin.dart';
import 'package:movera_rider/features/safety/domain/safety_event.dart';
import 'package:movera_rider/features/safety/domain/safety_preferences.dart';
import 'package:movera_rider/features/safety/domain/trip_share.dart';
import 'package:movera_rider/l10n/l10n.dart';

class SafetyController extends ChangeNotifier {
  SafetyController._({
    SafetyRepository? store,
    SafetyStore? session,
    EmergencyCallService? emergency,
    SafetyAudioService? audio,
    RideCheckService? rideCheck,
  })  : _events = store ?? SafetyRepository.shared,
        _session = session ?? SafetyStore.shared,
        emergency = emergency ?? EmergencyCallService.shared,
        audio = audio ?? SafetyAudioService(store: session ?? SafetyStore.shared),
        rideCheck = rideCheck ??
            RideCheckService(store: session ?? SafetyStore.shared) {
    // rider-u199: an interrupted recording ends; the Kit redraws.
    this.audio.addListener(notifyListeners);
  }

  @override
  void dispose() {
    audio.removeListener(notifyListeners);
    super.dispose();
  }

  factory SafetyController({
    SafetyRepository? store,
    SafetyStore? session,
    EmergencyCallService? emergency,
    SafetyAudioService? audio,
    RideCheckService? rideCheck,
  }) {
    final injected = store != null ||
        session != null ||
        emergency != null ||
        audio != null ||
        rideCheck != null;
    if (!injected) return shared;
    return SafetyController._(
      store: store,
      session: session,
      emergency: emergency,
      audio: audio,
      rideCheck: rideCheck,
    );
  }

  static SafetyController? _shared;
  static SafetyController get shared =>
      _shared ??= SafetyController._();

  /// FLOW-6: the ride is over, so a recording the rider started in the
  /// Safety Kit stops and is saved. Looks only at a controller that already
  /// exists: no recording can run without one.
  ///
  /// rider-u35: with [keepRideCheck] (the trip completed, and its summary
  /// still shows an open Ride check card with its own Stop control) a
  /// card recording for that ride keeps running; the card stops it.
  static Future<void> stopRecordingForRideEnd({
    bool keepRideCheck = false,
  }) async {
    final audio = _shared?.audio;
    final active = audio?.active;
    if (active == null) return;
    if (keepRideCheck &&
        active.deviceOnly &&
        RideCheckController.existing?.sessionFor(active.rideId) != null) {
      return;
    }
    await audio!.stopIfRecording(reason: 'ride_ended');
  }

  /// rider-u201: the session expired and Sign in replaced the trip screen,
  /// so no Stop control is left on screen. A running recording (the Safety
  /// Kit's or a Ride check card's) stops and is saved for the rider.
  static Future<void> stopRecordingForSessionExpiry() async {
    await _shared?.audio.stopIfRecording(reason: 'session_expired');
  }

  @visibleForTesting
  static set sharedForTest(SafetyController? controller) =>
      _shared = controller;

  static void resetShared() {
    // rider-u202: no recording outlives the rider's data.
    _shared?.audio.discardForWipe();
    RideCheckController.resetShared();
    _shared?.dispose();
    _shared = null;
    SafetyStore.resetShared();
    SafetyRepository.resetShared();
  }

  final SafetyRepository _events;
  final SafetyStore _session;
  final EmergencyCallService emergency;
  final SafetyAudioService audio;
  final RideCheckService rideCheck;
  bool loading = false;
  bool hasLoaded = false;
  String? error;

  List<SafetyEvent> get events => _events.events;

  SafetyPreferences get preferences => _session.preferences;
  RidePin get pin => _session.pin;
  List<EmergencyContact> get contacts => _session.contacts;
  RideCheckPolicy get rideCheckPolicy => _session.rideCheck;

  String pinStatusLabel() =>
      preferences.pinRequired ? L10n.current.on : L10n.current.off;

  String contactsStatusLabel() {
    if (contacts.isEmpty) return L10n.current.safetyContactsNone;
    return L10n.current.safetyContactsCount(contacts.length);
  }

  String shareStatusLabel() {
    if (!preferences.tripShareEnabled) return L10n.current.off;
    return preferences.tripShareMode == TripShareMode.auto
        ? L10n.current.safetyShareEveryRide
        : L10n.current.safetyShareManual;
  }

  String rideCheckStatusLabel() => rideCheckPolicy.enabled ? L10n.current.on : L10n.current.off;

  List<RideCheckEvent> pendingRideCheckEvents(String rideId) =>
      rideCheck.events().where((event) =>
          event.rideId == rideId &&
          event.status == RideCheckStatus.pending &&
          event.payload['kind'] != 'sos').toList();

  Future<void> refreshRideCheckEvents(String rideId) async {
    await rideCheck.refresh(rideId);
    notifyListeners();
  }

  Future<void> resolveRideCheck(RideCheckEvent event) async {
    await rideCheck.resolve(event);
    notifyListeners();
  }

  void _publishSnapshot() {
    reportSafetySnapshot(
      jsonEncode({
        'pinRequired': preferences.pinRequired,
        'contacts': contacts.length,
        'tripShareEnabled': preferences.tripShareEnabled,
        'rideCheckEnabled': rideCheckPolicy.enabled,
      }),
    );
  }

  void record(SafetyKind kind, {String? rideId}) {
    _events.add(SafetyEvent(kind: kind, at: DateTime.now(), rideId: rideId));
  }

  Future<bool> sos({String? rideId}) async {
    final id = rideId?.trim();
    if (id == null || id.isEmpty) return false;
    try {
      await rideCheck.sos(rideId: id);
      record(SafetyKind.sos, rideId: id);
      notifyListeners();
      return true;
    } catch (error, stackTrace) {
      AppLog.warning(
        'safety.sos.backend_failed',
        extra: {'rideId': id, 'error': error.toString()},
      );
      AppLog.error(
        'safety.sos.backend_failed.detail',
        error: error,
        stackTrace: stackTrace,
        extra: {'rideId': id},
      );
      rethrow;
    }
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _publishSnapshot();
    notifyListeners();
    try {
      await _session.load();
      AppLog.info('safety.loaded', extra: {
        'contacts': contacts.length,
        'pinRequired': preferences.pinRequired,
      });
      _publishSnapshot();
      // A check queued by `moveraSimulateRideCheck` opens on the ride's own
      // screen (RideCheckController), not here.
    } catch (err) {
      error = L10n.current.safetyLoadFailed;
      AppLog.error('safety.load_failed');
    } finally {
      loading = false;
      hasLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setPinRequired(bool value) async {
    error = null;
    try {
      await _session.patchPreferences(preferences.copyWith(pinRequired: value));
      record(SafetyKind.ridePin);
      AppLog.info('safety.pin.required', extra: {'on': value});
    } catch (_) {
      error = L10n.current.safetyPinUpdateFailed;
    }
    notifyListeners();
  }

  Future<void> rotatePin() async {
    error = null;
    try {
      await _session.rotatePin();
      AppLog.info('safety.pin.rotated');
    } catch (_) {
      error = L10n.current.safetyPinChangeFailed;
    }
    notifyListeners();
  }

  Future<void> addContact({
    required String name,
    required String phone,
    String relationship = 'Other',
    bool shareTrips = false,
  }) async {
    error = null;
    try {
      await _session.createContact(
        name: name,
        phone: phone,
        relationship: relationship,
        shareTrips: shareTrips,
      );
      AppLog.info('safety.contact.created');
    } on SafetyException catch (err) {
      error = err.message;
      rethrow;
    } catch (_) {
      error = L10n.current.safetyContactSaveFailed;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> editContact(EmergencyContact contact) async {
    error = null;
    try {
      await _session.updateContact(contact);
    } on SafetyException catch (err) {
      error = err.message;
      rethrow;
    } finally {
      notifyListeners();
    }
    if (!contact.shareTrips) await _unselectForTripShare(contact.id);
  }

  /// rider-u204: "Share trips" switched off in the contact editor also
  /// takes the contact out of the Trip share selection, so the two agree.
  Future<void> _unselectForTripShare(String id) async {
    final selected = preferences.tripShareContactIds;
    if (!selected.contains(id)) return;
    try {
      await _session.patchPreferences(
        preferences.copyWith(
          tripShareContactIds: [
            for (final item in selected)
              if (item != id) item,
          ],
        ),
      );
    } catch (err) {
      // Not sent the trip either way: startShare reads the contact.
      AppLog.warning(
        'safety.share.unselect_failed',
        extra: {'error': '$err'},
      );
    }
    notifyListeners();
  }

  Future<void> removeContact(String id) async {
    error = null;
    try {
      await _session.deleteContact(id);
    } catch (_) {
      error = L10n.current.safetyContactDeleteFailed;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// FLOW-15: a failed change is reported through [error] (and rethrown so
  /// the screen can say so) instead of escaping as an unhandled error.
  Future<void> makePrimary(String id) async {
    error = null;
    try {
      await _session.setPrimary(id);
    } catch (_) {
      error = L10n.current.safetyPrimaryChangeFailed;
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> setTripShare({
    bool? enabled,
    TripShareMode? mode,
    List<String>? contactIds,
  }) async {
    error = null;
    try {
      await _session.patchPreferences(
        preferences.copyWith(
          tripShareEnabled: enabled,
          tripShareMode: mode,
          tripShareContactIds: contactIds,
        ),
      );
    } catch (_) {
      error = L10n.current.safetyShareUpdateFailed;
    }
    notifyListeners();
  }

  /// rider-u204: the trip goes to the trusted contacts that exist now, are
  /// enabled, and are ticked on Trip share or marked "Share trips" (what
  /// the Trip share page shows as ticked), never to a stored id of a
  /// contact that was deleted or disabled.
  List<String> get tripShareRecipients {
    final selected = preferences.tripShareContactIds;
    return [
      for (final contact in contacts)
        if (contact.isEnabled &&
            (contact.shareTrips || selected.contains(contact.id)))
          contact.id,
    ];
  }

  Future<TripShare> startShare(String rideId) async {
    final share = await _session.startShare(
      rideId,
      contactIds: tripShareRecipients,
    );
    record(SafetyKind.shareTrip, rideId: rideId);
    notifyListeners();
    return share;
  }

  /// Rides already shared automatically (one share per ride).
  final Set<String> _autoShared = {};

  /// rider-u217: with Trip share on and "Automatically share every ride"
  /// chosen, the trip screen calls this when the trip starts. It shares the
  /// ride once with the trip-share contacts; with no such contact, or the
  /// mode off, it does nothing.
  Future<TripShare?> autoShareRide(String rideId) async {
    final id = rideId.trim();
    if (id.isEmpty || !_autoShared.add(id)) return null;
    try {
      if (!hasLoaded) await load();
      if (!preferences.tripShareEnabled ||
          preferences.tripShareMode != TripShareMode.auto ||
          tripShareRecipients.isEmpty) {
        return null;
      }
      final share = await startShare(id);
      AppLog.info(
        'safety.share.auto_started',
        extra: {'rideId': id, 'contacts': share.contactIds.length},
      );
      return share;
    } catch (error) {
      // A later trip screen for this ride may try again.
      _autoShared.remove(id);
      AppLog.warning(
        'safety.share.auto_failed',
        extra: {'rideId': id, 'error': '$error'},
      );
      return null;
    }
  }

  Future<void> stopShare(String rideId) async {
    await _session.stopShare(rideId);
    notifyListeners();
  }

  Future<void> setRideCheck(bool enabled) async {
    error = null;
    try {
      await rideCheck.setEnabled(enabled);
    } catch (_) {
      error = L10n.current.safetyRideCheckUpdateFailed;
    }
    notifyListeners();
  }
}
