import 'package:movera_rider/features/profile/domain/profile.dart';

/// The rider's profile as screens and [ProfileController] see it (FLOW-7).
///
/// `ProfileRepository` is the on-device copy; `SyncedProfileRepository`
/// keeps that copy as a cache and sends the name, language and
/// communication consents to the server.
abstract interface class RiderProfileRepository {
  RiderProfileData get current;

  String displayName();

  /// The device copy and, where there is one, the server copy.
  Future<void> hydrate();

  /// The device copy only; it never waits on the network.
  Future<void> hydrateLocal();

  /// Forgets the signed-out rider's profile in memory.
  void clearLocal();

  Future<RiderProfileData> save(RiderProfileData next);
}
