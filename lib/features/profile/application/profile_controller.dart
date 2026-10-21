import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:movera_rider/features/profile/data/profile_repository.dart';
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
  Future<void> update(RiderProfileData next) async {
    try {
      await _store.save(next);
    } finally {
      notifyListeners();
    }
  }
}
