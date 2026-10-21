import 'dart:async';

import 'package:movera_rider/core/web/web_search_interrupted.dart';
import 'package:movera_rider/features/ride_booking/application/search_interrupted_notice.dart';
import 'package:movera_rider/features/ride_booking/data/ride_snapshot_store.dart';

/// Whether Home, as it opens, should say the rider's ride search was
/// interrupted. Read once: both notes are cleared.
///
/// Two sources. The restore coordinator notes a ride it dropped
/// ([SearchInterruptedNotice.shared]). The web build also keeps a session
/// flag that says a ride was live when the last document ended. Since
/// R-web the snapshot survives a reload, a sign-in after an expired
/// session and so on, and the kept ride is resumed after Home has
/// mounted, so the flag alone is no proof the ride was lost: it counts
/// only when no live ride is stored any more (rider-u117).
/// The answer is synchronous unless the web flag has to be checked against
/// the stored ride.
FutureOr<bool> takeHomeSearchInterrupted() {
  final dropped = SearchInterruptedNotice.shared.take();
  final liveOnWeb = takeWebSearchInterrupted();
  if (dropped) return true;
  if (!liveOnWeb) return false;
  return _noLiveRideStored();
}

Future<bool> _noLiveRideStored() async {
  try {
    return await RideSnapshotStore.read() == null;
  } catch (_) {
    return true;
  }
}
