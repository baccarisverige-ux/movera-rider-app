import 'dart:convert';

import 'package:movera_rider/core/storage/preferences_store.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/profile/domain/rider_profile_repository.dart';

/// The profile kept on this device only (demo, and the cache under
/// `SyncedProfileRepository`).
class ProfileRepository implements RiderProfileRepository {
  ProfileRepository({this.storageKey = 'movera_profile_v1'});

  static const _legacyName = 'Ben Gleason';
  static const _legacyEmail = 'ben.gleason@movera.se';
  static const _legacyPhone = '+46 70 123 45 67';
  static const _legacyPhoto = 'assets/images/profile_img.webp';

  final String storageKey;
  RiderProfileData _profile = RiderProfileData.defaults();
  bool _hydrated = false;

  @override
  RiderProfileData get current => _profile;

  static const emptyDisplayName = 'Welcome to Movera';

  @override
  String displayName() {
    final name = _profile.name.trim();
    // D-024: a friendly greeting, not a literal placeholder.
    return name.isEmpty ? emptyDisplayName : name;
  }

  @override
  Future<void> hydrateLocal() => hydrate();

  @override
  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await PreferencesStore.load();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final loaded = RiderProfileData.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        final sanitized = _presentationOnly(_sanitizeLegacyDemoProfile(loaded));
        _profile = sanitized;
        final persisted = _presentationJson(sanitized);
        if (!_sameProfile(loaded, sanitized) ||
            jsonEncode(decoded) != jsonEncode(persisted)) {
          await prefs.setString(storageKey, jsonEncode(persisted));
        }
      }
    } catch (error, stackTrace) {
      AppLog.error(
        'profile.hydrate_failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Forgets the signed-out rider's profile in memory (UserDataWipe removes
  /// the stored copy). The next [hydrate] reads storage again.
  @override
  void clearLocal() {
    _profile = RiderProfileData.defaults();
    _hydrated = false;
  }

  @override
  Future<RiderProfileData> save(RiderProfileData next) async {
    final sanitized = _presentationOnly(next);
    _profile = sanitized;
    try {
      final prefs = await PreferencesStore.load();
      await prefs.setString(
        storageKey,
        jsonEncode(_presentationJson(sanitized)),
      );
    } catch (error, stackTrace) {
      AppLog.error('profile.save_failed', error: error, stackTrace: stackTrace);
      rethrow;
    }
    return _profile;
  }

  Map<String, dynamic> _presentationJson(RiderProfileData source) => {
    'name': source.name,
    'gender': source.gender,
    'language': source.language,
    'photoAsset': source.photoAsset,
    'rideUpdates': source.rideUpdates,
    'promotions': source.promotions,
    'emailUpdates': source.emailUpdates,
  };

  RiderProfileData _presentationOnly(RiderProfileData source) {
    return source.copyWith(
      email: '',
      phone: '',
      passkeyEnabled: false,
      twoStepEnabled: false,
      authenticatorEnabled: false,
      passwordUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      googleConnected: false,
      appleConnected: false,
      logins: const [],
      clearRecovery: true,
    );
  }

  RiderProfileData _sanitizeLegacyDemoProfile(RiderProfileData source) {
    final hasLegacyIdentitySeed =
        source.email == _legacyEmail && source.phone == _legacyPhone;
    final hasLegacyLoginSeed =
        source.logins.length == 2 &&
        source.logins[0].device == 'This browser' &&
        source.logins[0].place == 'Stockholm, Sweden' &&
        source.logins[0].source == 'Movera Web' &&
        source.logins[0].current &&
        source.logins[1].device == 'iPhone' &&
        source.logins[1].place == 'Stockholm, Sweden' &&
        source.logins[1].source == 'Movera iOS' &&
        !source.logins[1].current;

    return source.copyWith(
      name: source.name == _legacyName ? '' : source.name,
      email: source.email == _legacyEmail ? '' : source.email,
      phone: source.phone == _legacyPhone ? '' : source.phone,
      gender: hasLegacyIdentitySeed && source.gender == 'Man'
          ? ''
          : source.gender,
      photoAsset: source.photoAsset == _legacyPhoto ? '' : source.photoAsset,
      passwordUpdatedAt: source.passwordUpdatedAt == DateTime(2025, 11, 4)
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : source.passwordUpdatedAt,
      appleConnected: hasLegacyIdentitySeed ? false : source.appleConnected,
      logins: hasLegacyLoginSeed ? const [] : source.logins,
    );
  }

  bool _sameProfile(RiderProfileData a, RiderProfileData b) {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }
}
