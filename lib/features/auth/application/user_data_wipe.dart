import 'dart:async';
import 'dart:convert';

import 'package:movera_rider/app/di.dart';
import 'package:movera_rider/core/api/safety_mock_api.dart';
import 'package:movera_rider/core/location/location_repository.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/core/web/web_search_interrupted.dart';
import 'package:movera_rider/features/auth/application/fresh_install_reset.dart';
import 'package:movera_rider/features/finding_driver/application/finding_driver_controller.dart';
import 'package:movera_rider/features/finding_driver/data/pending_cancel_store.dart';
import 'package:movera_rider/features/messages/data/messages_repository.dart';
import 'package:movera_rider/features/notifications/data/notifications_repository.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';
import 'package:movera_rider/features/ride_complete/data/last_completed_ride.dart';
import 'package:movera_rider/features/safety/application/safety_controller.dart';
import 'package:movera_rider/features/safety/application/safety_recorder.dart';
import 'package:movera_rider/features/safety/data/secure_ride_pin_store.dart';

/// Removes everything a rider left on this device (FLOW-1, ARCH-15).
///
/// One place, so a new per-user store cannot be forgotten: every
/// SharedPreferences key that starts with `movera_` is per-user and removed
/// unless it is listed in [deviceKeys]. Decisions, key by key:
///
/// Kept (device level, the same for whoever uses the phone):
/// - `movera_onboarding_done`: the intro was seen on this device.
/// - `movera_ride_catalog_v1`: the public ride categories from the admin
///   panel; no rider data in it.
/// - `movera_app_language`: the app language picked in Account (Q48); Sign
///   in speaks it too.
/// - `movera_install_seen`: this install has started before
///   ([FreshInstallReset], rider-u17).
///
/// Removed (per user):
/// - `movera_profile_v1` (name, photo, settings), `movera_rider_name_pending`
///   (a new rider's name step not done yet), `movera_rider_fingerprint`
///   (who was signed in, see [enterSessionAs]),
///   `movera_rider_session_started_at` (since when, rider-r5-44).
/// - `movera_home_address`, `movera_work_address`, `movera_saved_places`,
///   `movera_recent_addresses`, `movera_previous_pickups_v1`.
/// - `movera_saved_cards`, `movera_default_payment`, `movera_payment_methods`,
///   `movera_payment_business`, `movera_wallet_first`,
///   `movera_wallet_balance`, `movera_wallet_charged_rides` and the legacy
///   voucher keys (`movera_voucher_code`, `movera_voucher_amount`,
///   `movera_voucher_expires`, `movera_used_vouchers`).
/// - `movera_reservations_v1`, `movera_on_demand_ride_history_v1`,
///   `movera_active_ride` (the live ride snapshot, via [RideSnapshotStore]).
/// - `movera_safety_cache_v1` (trusted contacts, PIN placeholder, ride check),
///   `movera_safety_demo_v1` (the demo Safety mock's saved state; its
///   in-memory copy is reset too)
///   and the `movera_ride_pin` secure-storage entry.
/// - The Safety audio files in `<documents>/safety_recordings` (native).
/// - `movera_pending_cancels`: flushed first while the rider's own session is
///   still valid (sign-out only), then dropped. Once the tokens are gone no
///   one can send them as that rider, and sending them later with another
///   rider's session would cancel nothing or the wrong thing. The server
///   still owns the ride and its search expiry.
/// - `movera.location.last_good_fix.v1` (not `movera_` prefixed): the last
///   GPS position, via [LocationRepository.clearLastGoodFix]. Its zone
///   (`movera.location.last_zone.v1`, a country, no position) is a device
///   setting and stays, so the next cold start keeps the zone's default
///   language (rider-r4-41).
///
/// Not prefs: the access/refresh tokens (`movera_access_token`,
/// `movera_refresh_token`, secure storage or web localStorage, plus any
/// sessionStorage copy from older builds) are cleared by
/// `AuthRepository.signOut`; `movera_search_live` (web sessionStorage) is
/// cleared here. In memory: profile, saved places, saved cards, default
/// payment, wallet ledger, reservations, account security, promotion,
/// safety, notifications feed, ride chats, ride session, pickup and
/// destination drafts, the last completed ride and the live search
/// controller.
abstract final class UserDataWipe {
  static const riderFingerprintKey = 'movera_rider_fingerprint';

  static const deviceKeys = <String>{
    'movera_onboarding_done',
    'movera_ride_catalog_v1',
    'movera_app_language',
    FreshInstallReset.markerKey,
  };

  static const _flushBudget = Duration(seconds: 5);

  /// Sends queued cancels with the session that is still valid. Best effort:
  /// a failure or a slow network never blocks sign-out.
  static Future<void> flushPendingCancels() async {
    try {
      if ((await PendingCancelStore.all()).isEmpty) return;
      await FindingDriverController.flushPendingCancels().timeout(_flushBudget);
    } catch (error) {
      AppLog.warning(
        'auth.wipe.pending_cancels_dropped',
        extra: {'error': error.toString()},
      );
    }
  }

  /// Removes every per-user store and resets the in-memory state. Tokens
  /// are not touched here: sign-out clears them, and a new rider signing in
  /// has just saved theirs.
  static Future<void> run() async {
    // rider-u68: a flush the sign-out budget gave up on keeps running; it
    // must not write this rider's cancels back after the wipe.
    FindingDriverController.abandonPendingCancelFlush();
    resetInMemory();
    await RideSnapshotStore.clear();
    clearSearchLive();
    await LocationRepository.clearLastGoodFix();
    await const SecureRidePinStore().clear();
    await _deleteSafetyRecordings();
    try {
      final prefs = await PreferencesStore.load();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('movera_') && !deviceKeys.contains(key)) {
          await prefs.remove(key);
        }
      }
    } catch (error, stackTrace) {
      AppLog.error('auth.wipe_failed', error: error, stackTrace: stackTrace);
    }
    // Nothing is left to belong to anyone: anything that re-read storage
    // while the keys were going reads an empty store now.
    resetInMemory();
  }

  /// rider-u69 / rider-u71: the audio files themselves, not just their
  /// index in `movera_safety_cache_v1`.
  static Future<void> _deleteSafetyRecordings() async {
    try {
      await deleteAllSafetyRecordings();
    } catch (error) {
      AppLog.warning(
        'auth.wipe.recordings_failed',
        extra: {'error': error.toString()},
      );
    }
  }

  static void resetInMemory() {
    final scope = AppScope.instance;
    final finding = FindingDriverController.active;
    if (finding != null) {
      finding.dispose();
      FindingDriverController.active = null;
    }
    scope.ride.reset();
    scope.pickup
      ..address = null
      ..point = null;
    scope.destination
      ..address = null
      ..point = null;
    scope.profile.clearLocal();
    scope.savedPlaces.clearLocal();
    scope.savedCards.clearLocal();
    scope.payments.clearLocal();
    scope.wallet.clear();
    scope.reservations.clearLocal();
    scope.accountSecurity.clearLocal();
    scope.promotion.value = null;
    SafetyController.resetShared();
    // The demo transport's Safety "server" lives in memory and saves itself
    // to `movera_safety_demo_v1`; without this it wrote the previous rider's
    // PIN and contacts back after the wipe (PR-9 follow-up to FLOW-9).
    safetyMockForProcess().reset();
    NotificationsRepository.shared.clear();
    MessagesRepository.clearAllSessions();
    LastCompletedRide.clear();
  }

  /// Who the session belongs to: the token's `sub` when the backend sends
  /// one (contract C-1), else the verified phone number, else the provider.
  static String? riderIdFor({
    String? accessToken,
    String? phone,
    String? provider,
  }) {
    final sub = _subject(accessToken);
    if (sub != null) return 'sub:$sub';
    final number = phone?.replaceAll(' ', '').trim();
    if (number != null && number.isNotEmpty) return 'phone:$number';
    final name = provider?.trim();
    if (name != null && name.isNotEmpty) return 'provider:$name';
    return null;
  }

  /// Records that [riderId] is now signed in on this device. When a
  /// different rider was signed in before (the session expired rather than
  /// being signed out), their data is wiped first so nothing carries over.
  /// Returns true when it wiped.
  static Future<bool> enterSessionAs(String riderId) async {
    final fingerprint = _fingerprint(riderId);
    final prefs = await PreferencesStore.load();
    final previous = prefs.getString(riderFingerprintKey);
    final wipe = previous != null && previous != fingerprint;
    if (wipe) {
      AppLog.info('auth.wipe.rider_changed');
      await run();
    }
    await prefs.setString(riderFingerprintKey, fingerprint);
    if (previous != fingerprint) {
      // rider-r5-44: a new rider on this device. Notifications sent before
      // now (still in the OS tray) belong to whoever was signed in before.
      await prefs.setString(
        sessionStartedKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    }
    return wipe;
  }

  /// When the signed-in rider first signed in on this device (a `movera_`
  /// key, so sign-out drops it). See [enterSessionAs].
  static const sessionStartedKey = 'movera_rider_session_started_at';

  /// The [sessionStartedKey] time, or null when unknown.
  static Future<DateTime?> sessionStartedAt() async {
    try {
      final raw = (await PreferencesStore.load()).getString(sessionStartedKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  static String? _subject(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final sub = payload is Map ? payload['sub'] : null;
      return sub is String && sub.trim().isNotEmpty ? sub.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// FNV-1a 64-bit: the raw phone number never sits in plain prefs, and
  /// only equality matters.
  static String _fingerprint(String value) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final unit in utf8.encode(value)) {
      hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
