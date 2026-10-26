import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';

class ActiveRideRepository {
  Future<RideSnapshot?> restore() => RideSnapshotStore.read();

  Future<void> save(RideSnapshot snapshot) => RideSnapshotStore.save(snapshot);

  /// Terminal History must be able to archive a legitimate long-running ride
  /// even after it is too old to qualify for automatic resume.
  Future<RideSnapshot?> historyCandidate() =>
      RideSnapshotStore.readForArchive();

  Future<void> clear() => RideSnapshotStore.clear();
}
