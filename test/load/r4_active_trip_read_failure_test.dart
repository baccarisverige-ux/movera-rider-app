import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/api/api_error.dart';
import 'package:movera_rider/features/ride_booking/application/ride_restore_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R4 wiring: the Home poll's default check goes through
/// RideRestoreCoordinator.adoptServerActiveTrip, which keeps Home as it is
/// on a failed GET /rider/trips/active (it returns null). The coordinator
/// now keeps that failure, so RiderTripWatch can back off and honour the
/// server's Retry-After.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  const busy = ApiError(
    code: 'unavailable',
    reason: 'server_busy',
    message: 'busy',
    statusCode: 503,
    retryAfter: Duration(seconds: 2),
  );

  test('a failed active-trip read is kept; an answer clears it', () async {
    var failing = true;
    final coordinator = RideRestoreCoordinator(
      resync: (_) async {},
      authRequired: () => false,
      serverActiveTrip: () async {
        if (failing) throw busy;
        return null;
      },
      pendingCancel: (_) async => null,
    );
    expect(await coordinator.adoptServerActiveTrip(), isNull);
    expect(coordinator.lastActiveTripReadFailure, same(busy));
    failing = false;
    expect(await coordinator.adoptServerActiveTrip(), isNull);
    expect(coordinator.lastActiveTripReadFailure, isNull);
  });
}
