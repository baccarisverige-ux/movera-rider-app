import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/ride_booking/application/ride_session.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_status.dart';
import 'package:movera_rider/features/ride_booking/domain/ride_transition.dart';

void main() {
  test('localTransition remains strict and rejects illegal client jumps', () {
    final session = RideSession();

    expect(
      () => session.localTransition(RideStatus.driverAssigned),
      throwsA(isA<InvalidRideTransition>()),
    );
    expect(session.status, RideStatus.idle);
  });

  test('backendReconcile accepts an authoritative jump', () {
    final session = RideSession();

    final applied = session.backendReconcile(
      RideStatus.driverAssigned,
      id: 'ride-1',
      version: 4,
      updatedAt: DateTime.utc(2026, 9, 23, 3),
    );

    expect(applied, isTrue);
    expect(session.rideId, 'ride-1');
    expect(session.status, RideStatus.driverAssigned);
    expect(session.authoritativeVersion, 4);
  });

  test('lower backend version cannot roll a ride backwards', () {
    final session = RideSession();
    session.backendReconcile(
      RideStatus.driverWaiting,
      id: 'ride-1',
      version: 8,
      updatedAt: DateTime.utc(2026, 9, 23, 4),
    );

    final applied = session.backendReconcile(
      RideStatus.findingDriver,
      id: 'ride-1',
      version: 7,
      updatedAt: DateTime.utc(2026, 9, 23, 5),
    );

    expect(applied, isFalse);
    expect(session.status, RideStatus.driverWaiting);
    expect(session.authoritativeVersion, 8);
  });

  test('same version duplicate is ignored', () {
    final session = RideSession();
    session.backendReconcile(
      RideStatus.driverAssigned,
      id: 'ride-1',
      version: 3,
      updatedAt: DateTime.utc(2026, 9, 23, 3),
    );

    final applied = session.backendReconcile(
      RideStatus.driverAssigned,
      id: 'ride-1',
      version: 3,
      updatedAt: DateTime.utc(2026, 9, 23, 4),
    );

    expect(applied, isFalse);
    expect(session.status, RideStatus.driverAssigned);
  });

  test('newer timestamp can order legacy projections without a version', () {
    final session = RideSession();
    session.backendReconcile(
      RideStatus.driverAssigned,
      id: 'ride-1',
      updatedAt: DateTime.utc(2026, 9, 23, 3),
    );

    expect(
      session.backendReconcile(
        RideStatus.driverWaiting,
        id: 'ride-1',
        updatedAt: DateTime.utc(2026, 9, 23, 4),
      ),
      isTrue,
    );
    expect(
      session.backendReconcile(
        RideStatus.findingDriver,
        id: 'ride-1',
        updatedAt: DateTime.utc(2026, 9, 23, 2),
      ),
      isFalse,
    );
    expect(session.status, RideStatus.driverWaiting);
  });

  test('new ride id resets backend ordering domain', () {
    final session = RideSession();
    session.backendReconcile(
      RideStatus.driverWaiting,
      id: 'ride-old',
      version: 99,
      updatedAt: DateTime.utc(2026, 9, 23, 6),
    );

    final applied = session.backendReconcile(
      RideStatus.findingDriver,
      id: 'ride-new',
      version: 1,
      updatedAt: DateTime.utc(2026, 9, 23, 1),
    );

    expect(applied, isTrue);
    expect(session.rideId, 'ride-new');
    expect(session.status, RideStatus.findingDriver);
    expect(session.authoritativeVersion, 1);
  });

  test('terminal backend projection suppresses restore', () {
    final session = RideSession();

    session.backendReconcile(
      RideStatus.cancelledBySystem,
      id: 'ride-1',
      version: 5,
    );

    expect(session.status, RideStatus.cancelledBySystem);
    expect(session.suppressRestore, isTrue);
  });

  group('Phase 135: restore must seed authoritativeVersion', () {
    test('reproduces the bug: without a seeded version, a freshly-reconnected '
        "transport's low-numbered reset event is wrongly accepted, regressing "
        'a restored ride back to findingDriver', () {
      final session = RideSession();
      // The old RideRestoreCoordinator.pageFor call: no version, no
      // updatedAt, so authoritativeVersion stays null after this.
      session.backendReconcile(RideStatus.driverAssigned, id: 'ride-1');
      expect(session.authoritativeVersion, isNull);

      // A fresh MockRideRealtime construction resets its own sequence
      // counter to 0, so its first real event after reconnect carries a
      // low version number - 1, in this case - even though this ride had
      // already progressed further before the reload.
      final regressed = session.backendReconcile(
        RideStatus.findingDriver,
        id: 'ride-1',
        version: 1,
        updatedAt: DateTime.now(),
      );

      expect(
        regressed,
        isTrue,
        reason:
            'nothing was seeded to compare against, so the stale reset '
            'was wrongly accepted - this is the bug',
      );
      expect(session.status, RideStatus.findingDriver);
    });

    test('fixed: seeding authoritativeVersion from the restored snapshot '
        "rejects that same low-numbered reset event", () {
      final session = RideSession();
      // The fixed RideRestoreCoordinator.pageFor call: seeds version from
      // the snapshot's own persisted ordering number.
      session.backendReconcile(
        RideStatus.driverAssigned,
        id: 'ride-1',
        version: 5,
        updatedAt: DateTime.utc(2026, 9, 23, 10),
      );
      expect(session.authoritativeVersion, 5);

      final regressed = session.backendReconcile(
        RideStatus.findingDriver,
        id: 'ride-1',
        version: 1,
        updatedAt: DateTime.now(),
      );

      expect(
        regressed,
        isFalse,
        reason: 'version 1 is older than the seeded version 5',
      );
      expect(
        session.status,
        RideStatus.driverAssigned,
        reason: 'the restored ride must not regress',
      );
    });
  });
}
