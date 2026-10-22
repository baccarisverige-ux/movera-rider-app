import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/core/logging/app_log.dart';
import 'package:movera_rider/features/profile/application/app_language_controller.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
import 'package:movera_rider/features/profile/data/synced_profile_repository.dart';
import 'package:movera_rider/features/profile/domain/profile.dart';
import 'package:movera_rider/features/profile/domain/rider_profile_repository.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({RiderProfileRepository? store})
    : _store = store ?? ProfileRepository();

  final RiderProfileRepository _store;

  /// The repository behind this controller, for the composition guard.
  RiderProfileRepository get repository => _store;

  RiderProfileData get profile => _store.current;

  String displayName() => _store.displayName();

  Future<void> hydrate() async {
    await _store.hydrate();
    notifyListeners();
  }

  /// [hydrate] at sign-in, then (rider-r5-42) a language the rider picked
  /// on this device before signing in, which could not be saved without
  /// a session, goes to the server profile: the server speaks to the rider
  /// in the language the app speaks.
  Future<void> hydrateWithLanguage(AppLanguageController language) async {
    await hydrate();
    final store = _store;
    if (store is SyncedProfileRepository && !store.serverKnown) return;
    if (language.choice == null) return;
    final code = language.code;
    if (profile.language == code) return;
    try {
      await update(profile.copyWith(language: code));
    } catch (error) {
      AppLog.warning('language.profile_save_failed', extra: {'error': '$error'});
    }
  }

  /// rider-u148: the device copy now, the server copy when it arrives, so a
  /// slow network does not hold up the app.
  Future<void> hydrateLocalThenServer() async {
    await _store.hydrateLocal();
    notifyListeners();
    unawaited(hydrate());
  }

  /// Drops the in-memory profile at the end of a rider's session.
  void clearLocal() {
    _store.clearLocal();
    notifyListeners();
  }

  /// Throws when the save failed or the server refused it (rider-u150);
  /// listeners hear about the profile either way.
  ///
  /// rider-u154: the repository takes the change on the device before it
  /// waits on the server, so listeners hear about it at once too: a switch
  /// moves when it is tapped, and the next change starts from this one.
  Future<void> update(RiderProfileData next) async {
    final saving = _store.save(next);
    notifyListeners();
    try {
      await saving;
    } finally {
      notifyListeners();
    }
  }
}
